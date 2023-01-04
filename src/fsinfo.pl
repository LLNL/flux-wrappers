#!/usr/bin/perl

use warnings;
use strict;

sub print_usage(){
    print "Usage: $0 [-R] [-h|--noheader]\n";
    print " Display information about resource status.\n\n";
    print " Options:\n";
    print "  -R              display information about drained nodes\n";
    print "  -h|--noheader   do not print a header line\n";
    print "  -v|--verbose    show underlying flux command";
    exit 1;
}

sub print_warn($){
    my ($eargs) = @_;
    $eargs =~ s/^\s+//;
    print "Warning: $0 is a wrapper script and does not have all Slurm options implemented.\n";
    print "'$eargs' were ignored.\n";
    print "See '$0 --help' for supported options.\n\n";
}

sub run_drain{
    #my ($h,$v) = @_;
    my %params = @_;
    open CMD, "flux resource drain |" or die "$0 couldn't run 'flux resource drain'.\n";
    if( $params{verbose} ){
        print "#running : flux resource drain"
    }
    if( $params{header} ){
        print "REASON               USER      TIMESTAMP           NODELIST\n";
    }
    <CMD>;
    while( <CMD> ){
        my @line = split;
        my $timestamp = shift @line;
        my $state = shift @line;
        my $rank = shift @line;
        my $nodelist = pop @line;
        my $reason = join( ' ', @line );
        printf( "%-20.20s %-9.9s %-19.19s %s\n", $reason, "root", $timestamp, $nodelist);
    }
    close CMD;
}

sub run_list{
    #my ($h,$v) = @_;
    my %params = @_;
    open CMD, "flux resource list -o '{nnodes} {state} {nodelist}'|" or die "$0 couldn't run 'flux resource list'.\n";
    if( $params{verbose} ){
        print "#running : flux resource list\n"
    }
    if( $params{header} ){
        print "PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST\n";
    }
    <CMD>;
    while( <CMD> ){
        my( $nnodes, $state, $nodelist ) = split;
        if( $state =~ /free/ ){
            $state = 'idle';
        }elsif( $state =~ /alloc/ ){
            $state = 'alloc';
        }
        printf( "pdebug       up    1:00:00  %4d %6.6s %s\n", $nnodes, $state, $nodelist );
    }
    close CMD;
}

### Main ####

my $drain = '';
my $header = 1;
my $verbose = 0;
my $extraargs = '';
foreach my $arg (@ARGV) {
    if( $arg eq '-R' ){
        $drain = "true";
    }elsif( $arg eq '-h' or $arg eq '--noheader' ){
        $header = 0;
    }elsif( $arg eq '-v' or $arg eq '--verbose' ){
        $verbose = 1;
    }elsif( $arg eq '--help' ){
        print_usage;
    }else{
        $extraargs = " ".$arg;
    }
}

if( $extraargs ){
    print_warn( $extraargs );
}

if( $drain ){
    run_drain(
        header => $header,
        verbose => $verbose);
}else{
    run_list(
        header => $header,
        verbose => $verbose);
}
