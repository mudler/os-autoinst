# Copyright (C) 2017 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License

package osutils;

require 5.002;
use strict;
use warnings;

use Carp;
use base 'Exporter';
use Mojo::File 'path';
use Mojo::Loader qw(find_modules load_class);

our @EXPORT_OK = qw(
  dd_gen_params
  find_bin
  gen_params
  looks_like_ip
  load_module
  load_components
  get_class_name
  qv
  attempt
);

sub get_class_name { (split(/=/, "$_[0]"))[0] }

sub load_module {
    my ($module, $args, $phases) = ref $_[0] eq 'HASH' ? (@{$_[0]}{qw(name args phases)}) : @_;
    $phases ||= [];
    $args ||= [];
    my $loaded_module;
    eval { $loaded_module = $module->new(@$args); };
    return if $@;
    eval { $loaded_module->$_ } for grep { $loaded_module->can($_) } @$phases;

    return $loaded_module;
}

sub load_components {
    my ($namespace, $component, $args,$check_load, $phases) = ref $_[0] eq 'HASH' ? (@{$_[0]}{qw(namespace component args check_load phases)}) : @_;
    $phases ||= [];
    $args ||= [];
    $check_load ||= 0;

    my (@errors, @loaded);
    for my $module (find_modules $namespace) {
        next if $component && ($module !~ /$component/);
        my $e = load_class $module;
        if (ref $e) {
            push(@errors, $e);
            next;
        }
        next if $check_load && eval { !$module->new->load };

        if (defined(my $loaded_module = load_module($module, $args, $phases))) {
            push @loaded, $loaded_module;
        }
    }
    return \@errors, \@loaded;
}

sub looks_like_ip {
    my $part = qr/\d{1,2}|[01]\d{2}|2[0-4]\d|25[0-5]/;
    if ($_[0] =~ /^($part\.){3}$part$/) {
        return 1;
    }
    return 0;
}

# An helper to lookup into a folder and find an executable file between given candidates
# First argument is the directory, the remainining are the candidates.
sub find_bin {
    my ($dir, @candidates) = @_;

    foreach my $t_bin (map { path($dir, $_) } @candidates) {
        return $t_bin if -e $t_bin && -x $t_bin;
    }
    return;
}

## no critic
# An helper to full a parameter list, typically used to build option arguments for executing external programs.
# mimics perl's push, this why it's a prototype: first argument is the array, second is the argument option and the third is the parameter.
# the (optional) fourth argument is the prefix argument for the array, if not specified '-' (dash) is assumed by default
# if the parameter is equal to "", the value is not pushed to the array.
sub gen_params(\@$$;$) {
    my ($array, $argument, $parameter, $prefix) = @_;

    return unless ($parameter);
    $prefix = "-" unless $prefix;

    if (ref($parameter) eq "") {
        push(@$array, "${prefix}${argument}", $parameter);
    }
    elsif (ref($parameter) eq "ARRAY") {
        push(@$array, "${prefix}${argument}", join(',', @$parameter));
    }

}

# doubledash shortcut version. Same can be achieved with gen_params.
sub dd_gen_params(\@$$) {
    my ($array, $argument, $parameter) = @_;
    gen_params(@{$array}, $argument, $parameter, "--");
}

# It merely splits a string into pieces interpolating variables inside it.
# e.g.  gen_params @params, 'drive', "file=$basedir/l$i,cache=unsafe,if=none,id=hd$i,format=$vars->{HDDFORMAT}" can be rewritten as
#       gen_params @params, 'drive', [qv "file=$basedir/l$i cache=unsafe if=none id=hd$i format=$vars->{HDDFORMAT}"]
sub qv($) {
    split /\s+|\h+|\r+/, $_[0];
}
## use critic

sub attempt {
    my $attempts = 0;
    my ($total_attempts, $condition, $cb, $or) = ref $_[0] eq 'HASH' ? (@{$_[0]}{qw(attempts condition cb or)}) : @_;
    until ($condition->() || $attempts >= $total_attempts) {
        warn "Attempt $attempts";
        $cb->();
        sleep 1;
        $attempts++;
    }
    $or->() if $or && !$condition->();
    warn "Attempts terminated!";
}

1;
