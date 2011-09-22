package App::ListOrgHeadlines;

use 5.010;
use strict;
use warnings;
use Log::Any qw($log);

use DateTime;
use Org::Parser;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(list_org_headlines);

# VERSION

our %SPEC;

my $today;
my $yest;

sub _process_hl {
    my ($file, $hl, $args, $res) = @_;

    return if $args->{from_level} && $hl->level < $args->{from_level};
    return if $args->{to_level}   && $hl->level > $args->{to_level};
    if (defined $args->{todo}) {
        return if $args->{todo} xor $hl->is_todo;
    }
    if (defined $args->{done}) {
        return if $args->{done} xor $hl->is_done;
    }
    if (defined $args->{state}) {
        return unless $hl->is_todo &&
            $hl->todo_state eq $args->{state};
    }
    if ($args->{has_tags} || $args->{lack_tags}) {
        my $tags = [$hl->get_tags];
        if ($args->{has_tags}) {
            for (@{ $args->{has_tags} }) {
                return unless $_ ~~ @$tags;
            }
        }
        if ($args->{lack_tags}) {
            for (@{ $args->{lack_tags} }) {
                return if $_ ~~ @$tags;
            }
        }
    }
    if (defined $args->{priority}) {
        my $p = $hl->todo_priority;
        return unless defined($p) && $args->{priority} eq $p;
    }

    my $ats = $hl->get_active_timestamp;
    my $days;
    $days = int(($ats->datetime->epoch - $today->epoch)/86400)
        if $ats;
    if (defined $args->{due_in}) {
        return unless $ats;
        my $met = $days <= $args->{due_in};
        if (!$met && $ats->_warning_period) {
            # try the warning period
            my $dt = $ats->datetime->clone;
            my $wp = $ats->_warning_period;
            $wp =~ s/(\w)$//;
            my $unit = $1;
            $wp = abs($wp);
            if ($unit eq 'd') {
                $dt->subtract(days => $wp);
            } elsif ($unit eq 'w') {
                $dt->subtract(weeks => $wp);
            } elsif ($unit eq 'm') {
                $dt->subtract(months => $wp);
            } elsif ($unit eq 'y') {
                $dt->subtract(years => $wp);
            } else {
                die "Can't understand unit '$unit' in timestamp's ".
                    "warning period: " . $ats->as_string;
                return;
            }
            $met++ if DateTime->compare($dt, $today) <= 0;
        }
        return unless $met;
    }

    my $r;
    if ($args->{detail}) {
        $r               = {};
        $r->{file}       = $file;
        $r->{title}      = $hl->title->as_string;
        $r->{due_date}   = $ats ? $ats->datetime : undef;
        $r->{priority}   = $hl->todo_priority;
        $r->{tags}       = [$hl->get_tags];
        $r->{is_todo}    = $hl->is_todo;
        $r->{is_done}    = $hl->is_done;
        $r->{todo_state} = $hl->todo_state;
        $r->{progress}   = $hl->progress;
        $r->{level}      = $hl->level;
    } else {
        if ($ats) {
            my $pl = abs($days) > 1 ? "s" : "";
            $r = sprintf("%s: %s (%s)",
                         $days == 0 ? "today" :
                             $days < 0 ? abs($days)." day$pl ago" :
                                 "in $days day$pl",
                         $hl->title->as_string,
                         $ats->datetime->ymd);
        } else {
            $r = $hl->title->as_string;
        }
    }
    push @$res, $r;
}

$SPEC{list_org_headlines} = {
    summary => 'List all headlines in all Org files',
    args    => {
        files => ['array*' => {
            of         => 'str*',
            arg_pos    => 0,
            arg_greedy => 1,
        }],
        todo => [bool => {
            summary => 'Filter headlines that are todos',
            default => 0,
        }],
        done => [bool => {
            summary => 'Filter todo items that are done',
        }],
        due_in => [int => {
            summary => 'Filter todo items which is due in this number of days',
            description => <<'_',

Note that if the todo's due date has warning period and the warning period is
active, then it will also pass this filter irregardless. Example, if today is
2011-06-30 and due_in is set to 7, then todo with due date <2011-07-10 > won't
pass the filter but <2011-07-10 Sun +1y -14d> will (warning period 14 days is
already active by that time).

_
        }],
        from_level => [int => {
            summary => 'Filter headlines having this level as the minimum',
            default => 1,
        }],
        to_level => [int => {
            summary => 'Filter headlines having this level as the maximum',
        }],
        state => [str => {
            summary => 'Filter todo items that have this state',
        }],
        detail => [bool => {
            summary => 'Show details instead of just titles',
            default => 0,
        }],
        has_tags => [array => {
            summary => 'Filter headlines that have the specified tags',
        }],
        lack_tags => [array => {
            summary => 'Filter headlines that don\'t have the specified tags',
        }],
        priority => [str => {
            summary => 'Filter todo items that have this priority',
        }],
        time_zone => [str => {
            summary => 'Will be passed to parser\'s options',
            description => <<'_',

If not set, TZ environment variable will be picked as default.

_
        }],
    },
};
sub list_org_headlines {
    my %args = @_;

    my $files = $args{files};
    return [400, "Please specify files"] if !$files || !@$files;

    $today = DateTime->today;
    $yest  = $today->clone->add(days => -1);

    my $orgp = Org::Parser->new;
    my @res;

    for my $file (@$files) {
        $log->debug("Parsing $file ...");
        my $opts = {time_zone => $args{time_zone} // $ENV{TZ}};
        my $doc = $orgp->parse_file($file, $opts);
        $doc->walk(
            sub {
                my ($el) = @_;
                return unless $el->isa('Org::Element::Headline');
                _process_hl($file, $el, \%args, \@res)
            });
    } # for $file

    [200, "OK", \@res];
}

1;
#ABSTRACT: List headlines in Org files
__END__

=head1 SYNOPSIS

 # See list-org-headlines script


=head1 DESCRIPTION


=head1 FUNCTIONS

None are exported, but they are exportable.

=cut
