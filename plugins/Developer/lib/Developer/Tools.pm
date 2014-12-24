package Developer::Tools;
use strict;
use warnings;

use MT::Template::Context;
use MT::Builder;
use Developer::Util qw( _trim );

sub _scheduled_job {
    my $app = MT->instance;
    my $allow_perl = $app->config( 'AllowPerlScript' );
    my $component = MT->component( 'Developer' );
    my $iter = MT->model( 'mtmljob' )->load_iter( { status => 2, interval => { not => 0 } },
                                                  { sort => 'priority', direction => 'ascend' } );
    my @tl = MT::Util::offset_time_list( time, undef );
    my $current_ts = sprintf '%04d%02d%02d%02d%02d%02d', $tl[5]+1900, $tl[4]+1, @tl[3,2,1,0];
    while ( my $job = $iter->() ) {
        my $run;
        my $interval = $job->interval;
        next if ( $interval > 6 );
        my $lastrun_on = $job->lastrun_on;
        if (! $lastrun_on ) {
            $lastrun_on = '19700101000000';
        }
        my $nextrun_on = $job->nextrun_on;
        if ( $interval == 1 ) {
            # Every time
            $run = 1;
        } elsif ( $interval == 2 ) {
            # One time
            if ( $nextrun_on ) {
                if ( $nextrun_on <= $current_ts ) {
                    $run = 1;
                } else {
                    next;
                }
            }
        } elsif ( $interval == 3 ) {
            # Hourly
            my $ymdh = substr( $current_ts, 0, 10 );
            my $l_ymdh = substr( $lastrun_on, 0, 10 );
            if ( $ymdh == $l_ymdh ) {
                next;
            }
            my $ms = substr( $current_ts, 10, 4 );
            my $r_ms = substr( $nextrun_on, 10, 4 );
            if ( $r_ms <= $ms ) {
                $run = 1;
            } else {
                next;
            }
        } else {
            # Daily = 4, Weekly = 5, Monthly = 6
            my $ymd = substr( $current_ts, 0, 8 );
            my $l_ymd = substr( $lastrun_on, 0, 8 );
            if ( $ymd == $l_ymd ) {
                next;
            }
            my $hms = substr( $current_ts, 8, 6 );
            my $r_hms = substr( $nextrun_on, 8, 6 );
            if ( $r_hms <= $hms ) {
                # $run = 1;
            } else {
                next;
            }
            my $detail = $job->detail;
            if ( $interval == 4 ) {
                $run = 1;
            } else {
                if (! $detail ) {
                    next;
                }
                my @details = split( /,/, $detail );
                if ( $interval == 5 ) {
                    my $wd = MT::Util::wday_from_ts( substr( $current_ts, 0, 4 ),
                                substr( $current_ts, 4, 2 ), substr( $current_ts, 6, 2 ) );
                    for my $d ( @details ) {
                        $d = MT::Util::trim( $d );
                        if ( $d eq $wd ) {
                            $run = 1;
                            last;
                        }
                    }
                    if (! $run ) {
                        next;
                    }
                } elsif ( $interval == 6 ) {
                    my $day = substr( $current_ts, 6, 2 );
                    $day = $day + 0;
                    for my $d ( @details ) {
                        $d = MT::Util::trim( $d );
                        $d = lc( $d );
                        if ( $d eq 'last' ) {
                            my ( $start, $end ) = MT::Util::start_end_month( $current_ts );
                            $d = substr( $end, 6, 2 );
                        }
                        $d = $d + 0;
                        if ( $d == $day ) {
                            $run = 1;
                            last;
                        }
                    }
                    if (! $run ) {
                        next;
                    }
                }
            }
        }
        if (! $run ) {
            next;
        }
        my $template = $job->text;
        my $out;
        if ( $job->evalscript && $allow_perl ) {
            if ( $job->evalscript ) {
                $template = _trim( $template );
                if ( $template !~ m/sub\s{0,}\{/m ) {
                    $template = "sub {\n" . $template . "\n}";
                }
                my $freq = MT->handler_to_coderef( $template );
                my $cb;
                $out = $freq->( @_ );
            }
        } else {
            $template = MT->instance->translate_templatized( $template );
            my $ctx = MT::Template::Context->new;
            $ctx->stash( 'mtmljob', $job );
            my $build = MT::Builder->new;
            my $tokens = $build->compile( $ctx, $template )
                or $app->log( $component->translate(
                    'Parse error: [_1]', $build->errstr ) );
            defined( $out = $build->build( $ctx, $tokens ) )
                or $app->log( $component->translate(
                    'Build error: [_1]', $build->errstr ) );
        }
        my $message = $component->translate( 'The Custom Handler were run : [_1]', $job->title );
        my $log = {
                message => $message,
                class => 'Custom Handler',
                level => 1,
                metadata => $out,
        };
        $app->log( $log );
        $job->lastrun_on( $current_ts );
        if ( $interval == 2 ) {
            $job->status( 1 );
        }
        $job->save or die $job->errstr;
    }
    return 1;
}

sub _app_test {
    my $app = MT->instance;
    return 'This is my test handler.';
}

sub _remove_old_onetimetoken {
    my $app = MT->instance;
    my $component = MT->component( 'Developer' );
    my $ttl = MT->config( 'OnetimeTokenTTL' );
    my $start = time() - $ttl;
    my $iter = MT->model( 'session' )->load_iter( { kind => 'DT', start => { '<' => $start } } );
    while ( my $session = $iter->() ) {
        $session->remove or die $session->errstr;
    }
    return 1;
}

1;