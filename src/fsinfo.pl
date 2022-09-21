#!/usr/bin/perl

use warnings;
use strict;

sub print_usage(){
    print "Usage: sinfo [-R] [-h|--noheader]\n";
    print " Display information about resource status.\n\n";
    print " Options:\n";
    print "  -R              display information about drained nodes\n";
    print "  -h|--noheader   do not print a header line\n";
    exit 1;
}

sub print_warn($){
    my ($eargs) = @_;
    $eargs =~ s/^\s+//;
    print "Warning: sinfo is a wrapper script and does not have all Slurm options implemented.\n";
    print "'$eargs' were ignored.\n";
    print "See 'sinfo --help' for supported options.\n\n";
}

sub run_drain($){
    my ($h) = @_;
    open CMD, "flux resource drain |" or die "$0 couldn't run 'flux resource drain'.\n";
    if( $h ){
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

sub run_list($){
    my ($h) = @_;
    open CMD, "flux resource list -o '{nnodes} {state} {nodelist}'|" or die "$0 couldn't run 'flux resource list'.\n";
    if( $h ){
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
my $extraargs = '';
foreach my $arg (@ARGV) {
    if( $arg eq '-R' ){
        $drain = "true";
    }elsif( $arg eq '-h' or $arg eq '--noheader' ){
        $header = 0;
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
    run_drain($header);
}else{
    run_list($header);
}
