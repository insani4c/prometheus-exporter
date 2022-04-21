package Prometheus::Metric::Format;
use strict;
use warnings;

use base 'Prometheus';

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