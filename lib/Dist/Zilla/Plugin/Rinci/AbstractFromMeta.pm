package Dist::Zilla::Plugin::Rinci::AbstractFromMeta;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
use namespace::autoclean;

with (
    'Dist::Zilla::Role::BeforeBuild',
    'Dist::Zilla::Role::FileMunger',
    'Dist::Zilla::Role::FileFinderUser' => {
        default_finders => [':InstallModules', ':ExecFiles'],
    },
);

use Data::Dump qw(dump);
use File::Spec::Functions qw(catfile);

sub _get_abstract_from_meta {
    my ($self, $filename) = @_;

    local @INC = @INC;
    unshift @INC, 'lib';

    my $content = do {
        open my($fh), "<", $filename or die "Can't open $filename: $!";
        local $/;
        ~~<$fh>;
    };

    # find out the package of the file
    my $pkg;
    if ($content =~ m{^\s*package\s+(\w+(?:::\w+)*)\s*;}m) {
        $pkg = $1;
    } else {
        $pkg = 'main';
    }

    # XXX if script, do()
    (my $mod_p = $filename) =~ s!^lib/!!;
    require $mod_p;

    no strict 'refs';
    my $metas = \%{"$pkg\::SPEC"};

    my $abstract;
    {
        if ($metas->{':package'}) {
            $abstract = $metas->{':package'}{summary};
            last if $abstract;
        }

        # list functions, sorted by the length of its metadata dump
        my @funcs =
            map {$_->[0]}
                sort {length($a->[1]) <=> length($b->[1])}
                    map { [$_, dump($metas->{$_})] }
                        grep {/\A\w+\z/} keys %$metas;
        if (@funcs) {
            $abstract = $metas->{ $funcs[0] }{summary};
            last if $abstract;
        }
    }

    #$self->log_debug(["Figured out abstract for %s: %s", $filename, $abstract])
    #    if $abstract;
    $abstract;
}

# btw, why does dzil need to know abstract for main module before build?
sub before_build {
   my $self  = shift;
   my $name  = $self->zilla->name;
   my $class = $name; $class =~ s{ [\-] }{::}gmx;
   my $filename = $self->zilla->_main_module_override ||
       catfile( 'lib', split m{ [\-] }mx, "${name}.pm" );

   $filename or die 'No main module specified';
   -f $filename or die "Path ${filename} does not exist or not a file";
   open my $fh, '<', $filename or die "File ${filename} cannot open: $!";

   my $abstract = $self->_get_abstract_from_meta($filename);
   die "Can't get abstract for main module " . $filename unless $abstract;

   $self->zilla->abstract($abstract);
   return;
}

sub munge_files {
    my $self = shift;
    $self->munge_file($_) for @{ $self->found_files };
}

sub munge_file {
    my ($self, $file) = @_;
    my $content = $file->content;

    # we don't support execfiles for now because we need to patch pericmd* first
    # to dump instead of run
    unless ($file->name =~ m!^lib/!) {
        $self->log_debug(["skipping %s for now: not a module", $file->name]);
        return;
    }

    unless ($content =~ m{^#[ \t]*ABSTRACT:[ \t]*([^\n]*)[ \t]*$}m) {
        $self->log_debug(["skipping %s: no # ABSTRACT directive found", $file->name]);
        return;
    }

    my $abstract = $1;
    if ($abstract =~ /\S/) {
        $self->log_debug(["skipping %s: Abstract already filled (%s)", $file->name, $abstract]);
        return;
    }

    $abstract = $self->_get_abstract_from_meta($file->name);

    unless (defined $abstract) {
        die "Can't figure out abstract for " . $file->name;
    }

    $content =~ s{^#\s*ABSTRACT:.*}{# ABSTRACT: $abstract}m
        or die "Can't insert abstract for " . $file->name;
    $self->log(["inserting abstract for %s (%s)", $file->name, $abstract]);
    $file->content($content);
}

__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Fill out abstract from Rinci metadata

=for Pod::Coverage .+

=head1 SYNOPSIS

In C<dist.ini>:

 [Rinci::AbstractFromMeta]

In your module/script:

 # ABSTRACT:

During build, abstract will be filled with summary from Rinci package metadata,
or Rinci function metadata (if there are more than one, will pick "the largest"
function, measured by the dump length).

If Abstract is already filled, will leave it alone.


=head1 DESCRIPTION

This plugin is another DRY module. If you have already put summaries in Rinci
metadata, why repeat it in the dzil Abstract?


=head1 SEE ALSO

L<Rinci>

L<Dist::Zilla::Plugin::Rinci::PodnameFromMeta>
