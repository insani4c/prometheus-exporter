package Prometheus;

use strict;
use warnings;
use Log::Log4perl;
use Time::HiRes qw/time/;

sub new {
    my($class, $args) = @_;

    $args    = {} unless defined $args;
    my $self = bless $args, (ref $class || $class);

    my $module_name = ref($self);
    $module_name    =~ s/::/./;
    $self->{logp}   = Log::Log4perl->get_logger($module_name);
    $self->{logp}->debug("$class initialized:");

    return $self;
}

1;