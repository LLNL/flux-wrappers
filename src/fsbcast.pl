#!/bin/perl

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use File::Basename;

sub print_usage(){
    print "Usage: $0 SOURCE DEST\n";
    print " Copy a file into DEST on all nodes in allocation.\n\n";
    print " Options:\n";
    print "  -j|--jobid=JOBID  run in a specific job (optional if already in an allocation)\n";
    print "  -v|--verbose      show underlying flux commands\n";
    exit 1;
}

sub print_warn($){
    my ($eargs) = @_;
    $eargs =~ s/^\s+//;
    print "Warning: $0 is a wrapper script and does not have all Slurm options implemented.\n";
    print "'$eargs' were ignored.\n";
    print "See '$0 --help' for supported options.\n\n";
}

sub check_allocation(){
    my $jobid = `flux getattr jobid`;
    unless( defined $jobid and $jobid =~ /^f/ ){
        print "Error: $0 must be run in a Flux allocation or with '-j JOBID'. Exiting.\n";
        exit 1;
    }
}

sub run_and_extract($$$$){
    my ($source, $dest, $jobid, $verbose) = @_;
    my $proxycmd = "";
    if( $jobid ){
        $proxycmd = "flux proxy $jobid ";
    }
    my $sourcearg = "$source";
    if( $source =~ /\~?^\// ){
        my( $filename, $dirname, $suffix) = fileparse($source);
        $sourcearg = "-C $dirname $filename";
        if( $suffix ){
            $sourcearg .= $suffix;
        }
    }
    my $createcmd = $proxycmd."flux archive create $sourcearg";
    if( $verbose ){
        print "#running: $createcmd\n";
    }
    `$createcmd`;
    my $mkdircmd = $proxycmd."flux exec -r all mkdir -p $dest";
    if( $verbose ){
        print "#running: $mkdircmd\n";
    }
    `$mkdircmd`;
    my $extractcmd = $proxycmd."flux exec -r all flux archive extract --waitcreate -C $dest";
    if( $verbose ){
        print "#running: $extractcmd\n";
    }
    `$extractcmd`;
    my $removecmd = $proxycmd."flux archive remove";
    if( $verbose ){
        print "#running: $removecmd\n";
    }
    `$removecmd`;
    if( $verbose ){
        print "#done\n";
    }
}

### Main ###

my $destination = pop @ARGV;
my $source = pop @ARGV;
unless( $source and $destination ){
    print_usage();
}

my $verbose = 0;
my $jobid = "";
GetOptions(
    "j|jobid=s"  => \$jobid,
    "v|verbose"  => \$verbose
);

my $extraargs = join " ", @ARGV;
if( $extraargs ){
    print_warn( $extraargs );
}

unless( $jobid ){
    check_allocation();
}

run_and_extract($source,$destination,$jobid,$verbose);
