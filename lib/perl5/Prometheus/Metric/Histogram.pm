package Prometheus::Metric::Histogram;
use strict;
use warnings;
use Data::Dumper;

use base qw/Prometheus::Metric::Factory Prometheus::Metric/;

use constant DEFAULT_BUCKETS  => [];

sub required_arguments {
    $_[1]->{buckets}  //= DEFAULT_BUCKETS;
}

#
# $bucket must a hash with: bucket_label => bucket_value
# E.g.:
#  $bucket = {"0.3"   => 1294.3345, 
#             "0.6"   => 45678.1457, 
#             "1.2"   => 9787819034, 
#            }
sub value {
    my ($self, $buckets, $sum, $count) = @_; 

    $self->{value}{buckets} = $buckets;
    $self->{value}{sum}     = $sum;
    $self->{value}{count}   = $count;
    $self->{logp}->debug("value:", Dumper($self->{value}));

    return $self->{value};
}

sub metric_text {
    my ($self) = @_;

    my $str = '';
    my $metric = $self->{name};
    $str .= "# HELP $metric ". $self->{desc}. "\n";
    $str .= "# TYPE $metric ". lc($self->{type}). "\n";

    foreach my $bucket (@{ $self->{buckets} }) {
        $str .= $metric."_bucket{le=$bucket} ".$self->{value}{buckets}{$bucket} . "\n";
    }
    $str .= $metric."_sum " . $self->{value}{sum} ."\n";
    $str .= $metric."_count " . $self->{value}{count} ."\n";

    $self->{logp}->debug("Formatted metric text: $str");
    return $str;
}

1;