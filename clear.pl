#!/usr/bin/env perl

my $pwd = $0; $pwd =~ s/[^\/]*$//;
exec "$pwd/clean.pl", @ARGV or die "Failed to execute: $!";
