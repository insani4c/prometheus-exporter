package Prometheus::Exporter;
use strict;
use warnings;

use base 'Prometheus';

use Prometheus::Metric;
use Prometheus::Metric::Factory;

use threads;
use threads::shared;
use HTTP::Daemon;
use HTTP::Status;
use HTTP::Response;
use Time::HiRes qw/time sleep/;
use Data::Dumper;

#our VERSION = '0.1.0';

# Defaults
use constant LISTEN_PORT          => 9367;
use constant MAX_THREADS          => 5;
use constant MAX_REQUEST_TIMEOUT  => 15;
use constant MAX_CLIENT_TIME      => 30;

my $thread_count :shared = 0;

#
# Metrics variable
#
# $self->register_metrics(
#    {
#        metrics_name = > ["type", "description", labels],
#        ...
#    }
#)
# the input for register_metrics() should be a hashref with the metric name as key 
# name. The keys point to a arrayref with the following elements:
# 0: The type of metric: Gauge, Counter, Histogram
# 1: The description of the metric
# 3: either undef or an arrayref of label pairs. Example: ["code=200", "code=404", "code=503"]. When used, the data returned must be an arrayref too, in the same order.

sub new {
    my($class, $args) = @_;

    my $self = $class->SUPER::new($args);

    $self->{logp}->debug("max_threads: ", $self->{max_threads});
    $self->{logp}->debug("max_request_timeout: ", $self->{max_request_timeout});
    $self->{logp}->debug("max_client_time: ", $self->{max_client_time});
    $self->{logp}->debug("listen_port: ", $self->{listen_port});

    return $self;
}

sub required_arguments {
    $_[1]    = {} unless defined $_[1];

    $_[1]->{max_threads}         //= MAX_THREADS;
    $_[1]->{max_request_timeout} //= MAX_REQUEST_TIMEOUT;
    $_[1]->{max_client_time}     //= MAX_CLIENT_TIME;
    $_[1]->{listen_port}         //= LISTEN_PORT;
}

sub run {
    my ($self) = @_;

    my $d = HTTP::Daemon->new(
        LocalPort => $self->{listen_port},
        ReuseAddr => 1,
        ReusePort => 1,
        Blocking  => 1,
        Listen    => 20,
        ) || die;
    
    $self->{logp}->info("Prometheus::Exporter started!");
    $self->{logp}->info("Server Address: ", $d->sockhost());
    $self->{logp}->info("Server Port: ", $d->sockport());
    
    # Accept connections from clients
    while (my $client = $d->accept) {
        my $request_start_time = time();
        $self->{logp}->debug("client request received at $request_start_time, from ", $client->peerhost);
        $client->autoflush(1);
    
        eval {
            local $SIG{ALRM} = sub { die "Request reached max timeout\n" };
    
            alarm($self->{max_request_timeout});
            while (1) {
                 $self->{logp}->debug("Current running threads: $thread_count of ", $self->{max_threads});
                if($thread_count < $self->{max_threads}){
                    $thread_count++;
                    alarm(0);
                    threads->create(
                        sub { $self->process_request($client, $request_start_time) }, 
                    )->detach();
                    last ;
                }
                else {
                    $self->{logp}->debug("Max threads ($thread_count:$self->{max_threads}) reached, sleep 0.3 seconds");
                    sleep 0.3;
                }
            }
            alarm(0);
        };
        if($@){
            chomp($@);
            $self->{logp}->error("$@ (threads:$thread_count)");
    
            $client->send_response( $self->generate_timeout_response("FAILED - Request not processed in time, aborting\n") );
            $client->force_last_request;
            $client->close;
            undef($client);
        }
    }
}

sub process_request {
    my ($self, $client, $request_start_time) = @_;
    my $tid = threads->tid();
    my $start_processing_time = time();
    $self->{logp}->debug("Start processing request in thread id:$tid");

    eval {
        $client->autoflush(1);

        # Read requests from clients
        while (my $r = $client->get_request()) {
            local $SIG{ALRM} = sub { die "Processing reached max timeout\n" };
            alarm($self->{max_client_time});

            # Only accept GET /metrics
            if ($r->method eq 'GET' and $r->uri->path eq "/metrics") {

                # printf "[%d][tid:%d][pid:%d] %s POST request received\n", time(), $tid, $$, $client->peerhost;
                $self->{logp}->debug("GET /metrics request received for thread id:$tid from ", $client->peerhost);
                my $content = $r->content;

                # Collect data
                my $data = $self->_collect($content);
                die "No data returned\n" unless defined $data;

                # Gather request statistics
                my $total_request_time    = time() - $request_start_time;
                my $total_processing_time = time() - $request_start_time;
                my $total_waiting_time    = $total_request_time - $total_processing_time;
                $self->{logp}->info("Request processed in thread:$tid ($thread_count:$self->{max_threads}), processing_time:$total_processing_time, request_time:$total_request_time, waiting_time:$total_waiting_time");

                # Send the response to client
                $client->send_response( $self->generate_text_reponse( $self->format_metrics_text($data) ) );
                $client->force_last_request;
            }
            else {
                $self->{logp}->error("Invalid request ($r->method $r->uri->path) in thread id:$tid");
                $client->send_error(RC_FORBIDDEN)
            }
            alarm(0);
        }
    };
    if($@){
        chomp($@);
        $self->{logp}->error("Client request failed: $@ (tid:$tid|threads:$thread_count)");
    }
    alarm(0);

    $client->close;
    undef($client);

    # thread_count is a shared thread variable
    --$thread_count;

    my $total_request_time = time() - $request_start_time;
    $self->{logp}->debug("Total thread time:$total_request_time, releasing thread tid:$tid (running threads:$thread_count)");

    threads->exit;
}

sub register_metrics {
    my ($self, $metrics_map) = @_;

    $self->{metrics_map} = $metrics_map;

    return;
}

sub register_collector {
    my ($self, $code_ref) = @_;

    $self->{_collector} = $code_ref;
}

sub _collect {
    my ($self, $data) = @_;

    unless( defined $self->{_collector} ){
        $self->{logp}->debug("No collector subref defined, aborting...");
        return;
    }

    $self->{metrics_factory} = Prometheus::Metric::Factory->new();
    foreach my $m (keys %{$self->{metrics_map}}){
        Prometheus::Metric->new({name => $m, %{ $self->{metrics_map}->{$m} }})
    };
    $self->{logp}->debug("Metrics Factory:", Dumper($self->{metrics_factory}->factory));


    return( &{ $self->{_collector} }($data) )
}

sub get_metric {
    my ($self, $metric_name) = @_;

    return $self->{metrics_factory}->factory($metric_name)
}

sub render {
    my ($self, $data) = @_;
    my @metrics = $self->{metrics_factory}->metrics;

    unless( scalar @metrics ){
        $self->{logp}->error("No metrics defined, aborting...");
        return
    }

    my $str = '';
    foreach my $metric (@metrics){
        $str .= $self->get_metric($metric)->metric_text;
    }

    undef($self->{metrics_factory});

    $self->{logp}->debug("Formatted metrics text: $str");
    return $str;
}

sub generate_text_reponse {
    my ($self, $message) = @_;

    my $response = $self->_generate_response_object(200, 'OK', 'text/plain');
    $response->content( $message );

    return $response;
}

sub generate_timeout_response {
    my ($self, $text) = @_;

    my $response = $self->_generate_response_object(504, 'Gateway Timeout', 'text/plain');
    $response->content( $text );

    return $response;
}

sub _generate_response_object {
    my ($self, $rc, $rv, $type) = @_;

    # Initiate a new response object and set some defaults
    my $response = HTTP::Response->new($rc, $rv);
    $response->header( 'Content-type'  => $type );
    $response->header( 'Cache-Control' => 'no-cache, no-store, must-revalidate' );
    $response->header( 'Pragma'        => 'no-cache' );
    $response->header( 'Expires'       => 0 );

    return $response
}

1;