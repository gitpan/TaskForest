# -*-perl-*-

################################################################################
#
# $Id: ErrLogger.pm 33 2008-05-26 20:48:52Z aijaz $
#
################################################################################

package TaskForest::ErrLogger;


use strict;
use warnings;
use TaskForest::Logs;
use Log::Log4perl;

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.10';
}

sub TIEHANDLE {
    my $class = shift;
    bless { log => $TaskForest::Logs::log } , $class;
}

sub PRINT {
    my $self = shift;
    $Log::Log4perl::caller_depth++;
    $self->{log}->error(@_);
    $Log::Log4perl::caller_depth--;
}

1;

