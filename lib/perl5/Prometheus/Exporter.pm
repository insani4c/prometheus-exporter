=head1 Prometheus::Exporter - An exporter classed with threads based on HTTP::Daemon
=cut
package Prometheus::Exporter;
use strict;
use warnings;
use threads;
use threads::shared;

use base 'Prometheus';

use Prometheus::Metric;
use Prometheus::Metric::Factory;

use HTTP::Daemon;
use HTTP::Status;
use HTTP::Response;
use Time::HiRes qw/time sleep/;
use Data::Dumper;

#our VERSION = '0.1.0';

=head2 Defaults used during constructing:

=over 2

=item * LISTEN_PORT           9367

=item * LISTEN_ADDR           '0.0.0.0'

=item * MAX_THREADS           5

=item * MAX_LISTEN_QUEUE      25

=item * MAX_REQUEST_TIMEOUT   15

=item * MAX_CLIENT_TIME       30

=back

=cut
use constant LISTEN_PORT          => 9367;
use constant LISTEN_ADDR          => '0.0.0.0';
use constant MAX_THREADS          => 5;
use constant MAX_LISTEN_QUEUE     => 25;
use constant MAX_REQUEST_TIMEOUT  => 15;
use constant MAX_CLIENT_TIME      => 30;

my $thread_count :shared = 0;

=head2 Constructor

The constructor calls basically the Prometheus constructor and logs the
defaults values.

=cut
sub new {
    my($class, $args) = @_;

    my $self = $class->SUPER::new($args);

    $self->{logp}->debug("max_threads: ", $self->{max_threads});
    $self->{logp}->debug("max_request_timeout: ", $self->{max_request_timeout});
    $self->{logp}->debug("max_client_time: ", $self->{max_client_time});
    $self->{logp}->debug("listen_port: ", $self->{listen_port});
    $self->{logp}->debug("listen_addr: ", $self->{listen_addr});
    $self->{logp}->debug("max listen queue: ", $self->{max_listen_queue});

    return $self;
}

=head2 required_arguments()

Verify if all required arguments are passed or add them with default values.
This is called automatically in the constructor.

=cut
sub required_arguments {
    $_[1]    = {} unless defined $_[1];

    $_[1]->{max_threads}         //= MAX_THREADS;
    $_[1]->{max_request_timeout} //= MAX_REQUEST_TIMEOUT;
    $_[1]->{max_client_time}     //= MAX_CLIENT_TIME;
    $_[1]->{max_listen_queue}    //= MAX_LISTEN_QUEUE;
    $_[1]->{listen_port}         //= LISTEN_PORT;
    $_[1]->{listen_addr}         //= LISTEN_ADDR;
}

=head2 run()

run() starts the HTTP::Daemon server in blocking mode.
It measures the request time of each client.
Client requests are processed in parallel using threads. A maximum number of 
threads can be configured in the constructor.

Each client request is then handled by process_request() in a separate thread. If the
maximum number of threads has been reached, the client request will be queued and checked 
again every 0.3 seconds.

=cut
sub run {
    my ($self) = @_;

    my $d = HTTP::Daemon->new(
        LocalPort => $self->{listen_port},
        LocalAddr => $self->{listen_addr},
        ReuseAddr => 1,
        ReusePort => 1,
        Blocking  => 1,
        Listen    => $self->{max_listen_queue},
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

=head2 process_request()

During request processing, the method will first collect metric data by calling _collect().
If metrics data was returned, the data will be rendered to Prometheus compatible text and returned
to the client in a HTTP response.

=cut
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
                $client->send_response( $self->generate_text_reponse( $self->render($data) ) );
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

=head2 register_metrics()

The metrics configuration should be provided as a hashref.

Example:

=begin text

    {
        test_gauge         => {type => "gauge",     desc => "A test metric"},
        test_gauge_labels  => {type => "gauge",     desc => "A test metric", labels => ["code=42", "code=99"]},
        test_counter       => {type => "counter",   desc => "A test metric"},
        test_histogram     => {type => "histogram", buckets => ['0.3', '0.6', '1.2', '+Inf']},
    }

=end text

=cut
sub register_metrics {
    my ($self, $metrics_map) = @_;

    $self->{metrics_map} = $metrics_map;

    return;
}

=head2 register_collector()

Takes a subref or coderef as argument

=cut
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