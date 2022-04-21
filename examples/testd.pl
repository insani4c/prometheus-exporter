#!/usr/bin/perl
use strict;
use warnings;
use Log::Log4perl;

use lib './lib/perl5';
use Prometheus::Exporter;

my $logini = q{
    log4perl.logger                          = INFO, shihaiLogfile
    log4perl.appender.shihaiLogfile          = Log::Log4perl::Appender::File
    log4perl.appender.shihaiLogfile.filename = /tmp/shihai.log
    log4perl.appender.shihaiLogfile.layout   = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.shihaiLogfile.layout.ConversionPattern = %d [%r ms][%P][%C][%M] %p %m%n
};

Log::Log4perl->init( \$logini );
$Log::Log4perl::caller_depth = 1;

my $exporter = Prometheus::Exporter->new({listen_port => 9090, max_threads => 5});
$exporter->register_metrics({
    test_metric        => {type => "gauge",   desc => "A test metric"},
    test_metric_labels => {type => "gauge",   desc => "A test metric", labels => ["code=42", "code=99"]},
    test_counter       => {type => "counter", desc => "A test metric"},
});

$exporter->register_collector(sub {
    my $timeout = int(rand(5));
    sleep $timeout;

    $exporter->{metrics_factory}->factory("test_metric")->value(rand(100));
    $exporter->{metrics_factory}->factory("test_metric_labels")->value([rand(42), rand(99)]);
    $exporter->{metrics_factory}->factory("test_counter")->value(int(rand(78)));
});

$exporter->run;