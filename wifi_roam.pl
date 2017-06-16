#!/usr/bin/env perl

use strict;
use warnings;
use 5.024;

use Data::Printer;


#TODO: add user id/permissions check
say 'Reminder: Need to run as root';
#TODO: any way to pledge to reduce permissions?

die 'Need only alphanumeric interface id, eg "iwm0"'
  unless (my $interface = shift) =~ /^[a-z]+\d+$/;

# read output from ifconfig
open my $ifconfig_fh, '-|', "/sbin/ifconfig $interface scan" or die "$!";
my @ifconfig_input = <$ifconfig_fh>;
close $ifconfig_fh;

my %current_wifi;
while ((my $line = shift @ifconfig_input) && !%current_wifi) {
  # look for current wifi line
  next unless $line =~ /^\s*ieee80211: (?<wifi_details>.+)$/;

  die 'Unable to parse current wifi details'
    unless $+{wifi_details} =~ m{
      ^ nwid  \s  (?<nwid>.+)             \s
        chan  \s  (?<chan>\d+)            \s
        bssid \s  (?<bssid>[\da-f:]+)     \s?
                  ((?<signal_pct>\d+)%)?  $
    }x;

  say 'Current wifi:';
  p %+;
  print "\n";

  %current_wifi = %+;
}

die 'Not able to parse wifi details' unless %current_wifi;

my $threshold = ($current_wifi{signal_pct} // 0) + 1;

# look for matching nwid -- ordered strongest to weakest signal
# and filter out current bssid
@ifconfig_input = grep {
   /nwid $current_wifi{nwid}/ &&
  !/$current_wifi{bssid}/
} @ifconfig_input;

my %new_wifi;
# check the rest of ifconfig's scan output for a bssid with a higher signal str
#for my $line (@ifconfig_input) {
while ((my $line = shift @ifconfig_input) && !%new_wifi) {
  next unless $line =~ m{
    chan  \s  (?<chan>\d+)         \s
    bssid \s  (?<bssid>[\da-f:]+)  \s
              (?<signal_pct>\d+)%
  }x;

  # exit at first match not greater than threshold, since it's ordered
  # highest to lowest signal strength
  say 'No stronger bssid to roam to' and exit 0
    unless $+{signal_pct} > $threshold;

  say 'Roaming to:';
  p %+;

  %new_wifi = %+;
}

#TODO: still need to check permissions for setting new chan and bssid
# success -- attempt to set new chan and bssid
die 'Failed to roam'
  unless system(
    '/sbin/ifconfig',
    "$interface",
    'chan',   "$new_wifi{chan}",
    'bssid',  "$new_wifi{bssid}"
  ) == 0;
