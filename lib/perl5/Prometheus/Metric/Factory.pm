package Prometheus::Metric::Factory;
use strict;
use warnings;

use base 'Prometheus';

my $container;

sub add_factory {
    my ($self) = @_;

    $Prometheus::Metric::Factory::container->{ $self->{name} } = $self;
    $self->{logp}->debug("Registered $self->{name} (". ref($self) .") in factory");
}

sub metrics {
    my ($self) = @_;

    return keys %{ $Prometheus::Metric::Factory::container }
}

sub factory {
    my ($self, $metric) = @_;

    return $Prometheus::Metric::Factory::container unless defined $metric;
    return $Prometheus::Metric::Factory::container->{$metric};
}

1;