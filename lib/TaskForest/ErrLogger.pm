# -*-perl-*-

################################################################################
#
# $Id: ErrLogger.pm 40 2008-06-03 00:07:40Z aijaz $
#
################################################################################

=head1 NAME

TaskForest::ErrLogger - Functions related to logging to stderr

=head1 DOCUMENTATION

This is a class that is used to tie prints to STDERR to $log->error();
See Logger::Log4perl for more details. 

=cut

package TaskForest::ErrLogger;


use strict;
use warnings;
use TaskForest::Logs;
use Log::Log4perl;

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.13';
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
