#!/usr/bin/perl
use strict;
use warnings;
use Log::Log4perl;
use threads;
use threads::shared;

use lib './lib/perl5';
use Prometheus::Exporter;

my $logini = q{
    log4perl.logger                          = DEBUG, shihaiLogfile
    log4perl.appender.shihaiLogfile          = Log::Log4perl::Appender::File
    log4perl.appender.shihaiLogfile.filename = /tmp/shihai.log
    log4perl.appender.shihaiLogfile.layout   = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.shihaiLogfile.layout.ConversionPattern = %d [%r ms][%P][%C][%M] %p %m%n
};

Log::Log4perl->init( \$logini );
$Log::Log4perl::caller_depth = 1;

# tagged with :shared to share them amongst threads
my $test_counter :shared  = 0;
my %histo_buckets :shared = ( "0.3" => 0, "0.6" => 0, "1.2" => 0, "+Inf" => 0 );

my $exporter = Prometheus::Exporter->new({
    listen_port => 9090, 
    listen_addr => "127.0.0.1", 
    max_threads => 5,
});

$exporter->register_metrics({
    test_metric        => {type => "gauge",     desc => "A test metric"},
    test_metric_labels => {type => "gauge",     desc => "A test metric", labels => ["code=42", "code=99"]},
    test_counter       => {type => "counter",   desc => "A test metric"},
    test_histogram     => {type => "histogram", buckets => ['0.3', '0.6', '1.2', '+Inf']},
});

$exporter->register_collector(sub {
    my $timeout = int(rand(5));
    sleep $timeout;

    $exporter->get_metric("test_metric")->value(rand(100));
    $exporter->get_metric("test_metric_labels")->value([rand(42), rand(99)]);

    $test_counter += int(rand(20));
    $exporter->get_metric("test_counter")->value($test_counter);

    $histo_buckets{"0.3"}  += rand(20);
    $histo_buckets{"0.6"}  += $histo_buckets{"0.3"} + rand(20);
    $histo_buckets{"1.2"}  += $histo_buckets{"0.6"} + rand(20);
    $histo_buckets{"+Inf"} += $histo_buckets{"1.2"} + rand(20);
    my $histo_sum = 2.0 * $histo_buckets{"+Inf"};
    my $histo_count = $histo_buckets{"+Inf"};
    $exporter->get_metric("test_histogram")->value(\%histo_buckets, $histo_sum, $histo_count);
});

$exporter->run;
