package Prometheus::Metric;
use strict;
use warnings;

use base qw/Prometheus/;
use Prometheus::Metric::Gauge;
use Prometheus::Metric::Counter;
use Prometheus::Metric::Histogram;
use Data::Dumper;

use constant DEFAULT_NAME => "unconfigured_metric";
use constant DEFAULT_TYPE => "gauge";
use constant DEFAULT_DESC => "An unconfigured metric";

sub new {
    my($class, $args) = @_;

    $class->required_arguments($args);

    if($args->{type} eq 'gauge'){
        $class = 'Prometheus::Metric::Gauge';
    }
    elsif($args->{type} eq 'counter'){
        $class = 'Prometheus::Metric::Counter';
    }
    elsif($args->{type} eq 'histogram'){
        $class = 'Prometheus::Metric::Histogram';
    }

    my $self = $class->new($args);

    $self->add_factory();

    return $self;
}

sub required_arguments {
    $_[1] = {} unless defined $_[1];

    $_[1]->{type} //= DEFAULT_TYPE;
    $_[1]->{desc} //= DEFAULT_DESC;
    $_[1]->{name} //= DEFAULT_NAME;
}


sub value {
    my ($self, $v) = @_; 

    $self->{value} = $v if defined $v;
    $self->{logp}->debug("value:", Dumper($self->{value}));

    return $self->{value};
}

sub label_value {
    my ($self, $label) = @_; 

    my ($index) = grep { $self->{labels}[$_] eq $label } (0 .. scalar @{ $self->{labels} } - 1);

    return unless defined $self->{value}[$index];
    $self->{logp}->debug("value $label:", $self->{value}[$index]);
    
    return $self->{value}[$index];
}

sub labels {
    my ($self) = @_;

    return $self->{labels}    
}

sub metric_text {
    my ($self) = @_;

    my $str = '';
    my $metric = $self->{name};
    $str .= "# HELP $metric ". $self->{desc}. "\n";
    $str .= "# TYPE $metric ". lc($self->{type}). "\n";

    if(defined $self->labels){
        foreach my $label (@{ $self->labels }) {
            $str .= $metric."{$label} ".$self->label_value($label) . "\n";
        }
    }
    else {
        $str .= $metric." " . $self->value ."\n";
    }

    $self->{logp}->debug("Formatted metric text: $str");
    return $str;

}

1;