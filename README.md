# prometheus-exporter

A set of Perl modules to build custom Prometheus exporter daemons.

The daemon is initialized with:
``` perl
use Prometheus::Exporter;
my $exporter = Prometheus::Exporter->new({
    listen_port => 9090, 
    listen_addr => "127.0.0.1", 
    max_threads => 5,
});
```

Metrics must be registered as:
``` perl
$exporter->register_metrics({
    test_metric        => {type => "gauge",     desc => "A test metric"},
    test_metric_labels => {type => "gauge",     desc => "A test metric", labels => ["code=42", "code=99"]},
    test_counter       => {type => "counter",   desc => "A test metric"},
    test_histogram     => {type => "histogram", buckets => ['0.3', '0.6', '1.2', '+Inf']},
});
```

Each daemon must have a collector sub routine or coderef configured, which does the actual polling of data.

Example:
``` perl
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
```

Finally, the exporter daemon is started with the run method:
``` perl
$exporter->run;
```

