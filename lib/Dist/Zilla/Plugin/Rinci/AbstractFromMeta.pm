package Dist::Zilla::Plugin::Rinci::AbstractFromMeta;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
use namespace::autoclean;

with (
    'Dist::Zilla::Role::FileMunger',
    'Dist::Zilla::Role::FileFinderUser' => {
        default_finders => [':InstallModules', ':ExecFiles'],
    },
);

use Perinci::Sub::Normalize qw(normalize_function_metadata);

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

    unless ($content =~ m{^#\s*ABSTRACT:\s*(.*?)\s*$}m) {
        $self->log_debug(["skipping %s: no # ABSTRACT directive found", $file->name]);
        return;
    }

    my $abstract = $1;
    if ($abstract =~ /\S/) {
        $self->log_debug(["skipping %s: Abstract already filled (%s)", $file->name, $abstract]);
        return;
    }

    # find the appropriate abstract
    {
        local @INC = @INC;
        unshift @INC, 'lib';

        # find out the package of the file
        my $package;
        if ($content =~ m{^\s*package\s+(\w+(?:::\w+)*)\s*;}m) {
            $package = $1;
        } else {
            $package = 'main';
        }

        # XXX if script, do()
        (my $mod_p = $file->name) =~ s!^lib/!!;
        require $mod_p;

        no strict 'refs';
        my $metas = \%{"$pkg\::SPEC"};

        if ($metas->{':package'}{summary}) {
            $abstract = $metas->{':package'}{summary};
            last;
        }
    }

    unless (defined $abstract) {
        die "Can't figure out abstract for " . $file->name;
    }

    $content =~ s{^#\s*ABSTRACT:.*}{# ABSTRACT: $summary}m
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
