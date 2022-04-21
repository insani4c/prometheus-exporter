package Prometheus::Metric;
use strict;
use warnings;

use base qw/Prometheus Prometheus::Metric::Format/;
use Prometheus::Metric::Gauge;
use Prometheus::Metric::Counter;
use Data::Dumper;

sub new {
    my($class, $args) = @_;

    if($args->{type} eq 'gauge'){
        $class = 'Prometheus::Metric::Gauge';
    }
    elsif($args->{type} eq 'counter'){
        $class = 'Prometheus::Metric::Counter';
    }

    $args    = {} unless defined $args;

    my $self = $class->new($args);
    $self->add_factory();

    return $self;
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

1;