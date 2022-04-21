package Prometheus;

use strict;
use warnings;
use Log::Log4perl;

sub new {
    my($class, $args) = @_;

    $class->required_arguments($args);

    my $self = bless $args, (ref $class || $class);

    my $module_name = ref($self);
    $module_name    =~ s/::/./;
    $self->{logp}   = Log::Log4perl->get_logger($module_name);
    $self->{logp}->debug("$class initialized:");

    return $self;
}

sub required_arguments {
    $_[1] = {} unless defined $_[1];
}

1;