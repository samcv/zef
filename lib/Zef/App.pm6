unit class Zef::App;

#core modes 
use Zef::Authority::P6C;
use Zef::Builder;
use Zef::Config;
use Zef::Installer;
use Zef::Test;
use Zef::Uninstaller;
use Zef::Utils::PathTools;

our $MAX-TERM-COLS = get-term-cols();

# Try to determine the terminal width to attempt pretty formatting
sub get-term-cols {
    if $*DISTRO.is-win {
        my $r    = run("mode", :out, :err);
        my $line = $r.out.lines.join("\n");
        if $line ~~ /'CON:' \n <.ws> '-'+ \n .*? \n \N+? $<cols>=[<.digit>+]/ {
            my $cols = $/<cols>.comb(/\d/).join;
            return +$cols - 1 if try { +$cols }
        }
        return 80 - 1;
    }
    else {
        my $r = run("tput", "cols", :out, :err);
        my $line = $r.out.lines.join;
        if $line ~~ /$<cols>=<.digit>+/ {
            my $cols = ~$/<cols>.comb(/\d/).join;
            return +$cols - 1 if try { +$cols }
        }
        return 120 - 1;
    }
}

# will be replaced soon
sub verbose($phase, @_) {
    return unless @_;
    my %r = @_.classify({ $_.hash.<ok> ?? 'ok' !! 'nok' });
    print "!!!> $phase failed for: {%r<nok>.list.map({ $_.hash.<module> })}\n" if %r<nok>;
    print "===> $phase OK for: {%r<ok>.list.map({ $_.hash.<module> })}\n"      if %r<ok>;
    return { ok => %r<ok>.elems, nok => %r<nok> }
}


# This works *much* better when using "\r" instead of some number of "\b"
# Unfortunately MoarVM on Windows has a bug where it prints "\r" as if it were "\n"
# (JVM is OK on windows, JVM/Moar are ok on linux)
sub show-await($message, *@promises) {
    my $loading = Supply.interval(1);
    my $out = $*OUT;
    my $err = $*ERR;
    my $in  = $*IN;

    $*ERR = $*OUT = class :: {
        my $lock = Lock.new;
        my $e;
        my $m;
        my $last-line-len = 0;

        $loading.tap(
        {
            $e = do given ++$m { 
                when 2  { "-==" }
                when 3  { "=-=" }
                when 4  { "==-" }
                default { $m = 1; "===" }
            }

            print r-print("");
        },
            done    => { print r-print(''); },
            closing => { print r-print(''); },
        );

        sub fake-carriage($len) { my Str $str = ("\b" x $len) || ''; ~$str }
        sub clear-line($len)    { my Str $str = (" "  x $len) || ''; ~$str }
        sub r-print($str = '', $last-len = 0) { 
            if $last-line-len {
                my $fc  = fake-carriage($last-len);
                my $cl  = clear-line($last-len);
                my $ret = "$fc$cl$fc$str";
            }
            else {
                return $str;
            }
        }

        method print(*@_) {
            my $lines = @_.join;
            $lock.protect({
                my $out2 = $*OUT;
                $*ERR = $*OUT = $out;
                if $lines.chars {
                    my $line = r-print($lines.trim-trailing, $last-line-len);
                    $line ~= "\n";
                    print $line;
                    $last-line-len = 0;
                }

                my $msg = "$e> $message...";
                my $status-bar = r-print($msg, $last-line-len);
                print $status-bar;
                $last-line-len = $msg.chars;
                $*ERR = $*OUT = $out2;
            });
        }

        method flush {}
    }


    await Promise.allof: @promises;
    $loading.close;
    $*ERR = $err;
    $*OUT = $out;
}


#| Test modules in the specified directories
multi MAIN('test', *@paths, Bool :$v) is export {
    my @repos = @paths ?? @paths !! $*CWD;


    # Test all modules (important to pass in the right `-Ilib`s, as deps aren't installed yet)
    # (note: first crack at supplies/parallelization)
    my $test-promise = Promise.new;
    my $test-vow     = $test-promise.vow;
    my $test-await   = start { show-await("Testing", $test-promise) };

    my @includes = gather for @repos -> $path {
        take $*SPEC.catdir($path, "blib");
        take $*SPEC.catdir($path, "lib");
    }
    my @t = @repos.map: -> $path { Zef::Test.new(:$path, :@includes) }
    my $longest = @t.list>>.test>>.list.reduce({ # for verbose output formatting
        $^a.file.IO.basename.chars > $^b.file.IO.basename.chars ?? $^a !! $^b
    }).file.IO.basename.chars if $v;
    for @t.list>>.test>>.list.grep({$v}) -> $tst {
        my $tfile = $tst.file.IO.basename;
        my $spaces = $longest - $tfile.chars;
        $tst.stdout.tap(-> $stdout {
            if $stdout.words {
                my $prefix = $tfile ~ (' ' x $spaces) ~ "# ";
                print $prefix ~ $stdout.subst(/\n/, "\n$prefix", :x( ($stdout.lines.elems // 1) - 1)).chomp ~ "\n";
            }
        });
        $tst.stderr.tap(-> $stderr {
            if $stderr.words {
                my $prefix = $tfile ~ (' ' x $spaces) ~ "# ";
                print $prefix ~ $stderr.subst(/\n/, "\n$prefix", :x( ($stderr.lines.elems // 1) - 1)).chomp ~ "\n";
            }
        });

    }
    await Promise.allof: @t.list>>.results>>.list>>.promise;
    $test-vow.keep(1);
    await $test-await;
    my $r = verbose('Testing', @t.list>>.results>>.list.map({ ok => all($_>>.ok), module => $_>>.file.IO.basename }));
    print "Failed tests. Aborting.\n" and exit $r<nok> if $r<nok>;


    exit 0;
}


#| Install with business logic
multi MAIN('install', *@modules, Bool :$report, IO::Path :$save-to = $*TMPDIR, Bool :$v) is export {
    my $SPEC := $*SPEC;
    my $auth  = Zef::Authority::P6C.new;

    # Download the requested modules from some authority
    # todo: allow turning dependency auth-download off
    my $get-promise = Promise.new;
    my $get-vow     = $get-promise.vow;
    my $get-await   = start { show-await("Fetching", $get-promise) };
    my @g = $auth.get: @modules, :$save-to;
    $get-vow.keep(1);
    await $get-await;
    verbose('Fetching', @g);


    # Ignore anything we downloaded that doesn't have a META.info in its root directory
    my @m = @g.grep({ $_<ok> }).map({ $_<ok> = ?$SPEC.catpath('', $_.<path>, "META.info").IO.e; $_ });
    verbose('META.info availability', @m);
    # An array of `path`s to each modules repo (local directory, 1 per module) and their meta files
    my @repos = @m.grep({ $_<ok> }).map({ $_.<path> });
    my @metas = @repos.map({ $SPEC.catpath('', $_, "META.info").IO.path });


    # Precompile all modules and dependencies
    my $build-promise = Promise.new;
    my $build-vow     = $build-promise.vow;
    my $build-await   = start { show-await("Building", $build-promise) };
    my @b = Zef::Builder.new.pre-compile: @repos;
    $build-vow.keep(1);
    await $build-await;
    verbose('Build', @b);


    # Test all modules (important to pass in the right `-Ilib`s, as deps aren't installed yet)
    # (note: first crack at supplies/parallelization)
    my $test-promise = Promise.new;
    my $test-vow     = $test-promise.vow;
    my $test-await   = start { show-await("Testing", $test-promise) };
    my @includes = gather for @repos -> $path {
        take $SPEC.catdir($path, "blib");
        take $SPEC.catdir($path, "lib");
    }
    my @t = @repos.map: -> $path { Zef::Test.new(:$path, :@includes) }
    my @test-files = @t.list>>.test-files>>.IO>>.basename; # For templating: `00-testfile.t[spaces]# [output]`
    my $longest = @test-files.reduce({ $^a.chars > $^b.chars ?? $^a !! $^b }).chars if $v; # Spaces needed for template^^
    for @t.list>>.test>>.list.grep({$v}) -> $tst { # Print verbose test output
        my $tfile  = $tst.file.IO.basename;
        my $spaces = $longest - $tfile.chars;
        $tst.stdout.tap(-> $stdout {
            if $stdout.words {
                my $prefix = $tfile ~ (' ' x $spaces) ~ "# ";
                print $prefix ~ $stdout.subst(/\n/, "\n$prefix", :x( ($stdout.lines.elems // 1) - 1)).chomp ~ "\n";
            }
        });
        $tst.stderr.tap(-> $stderr {
            if $stderr.words {
                my $prefix = $tfile ~ (' ' x $spaces) ~ "# ";
                print $prefix ~ $stderr.subst(/\n/, "\n$prefix", :x( ($stderr.lines.elems // 1) - 1)).chomp ~ "\n";
            }
        });

    }
    await Promise.allof: @t.list>>.results>>.list>>.promise;
    $test-vow.keep(1);
    await $test-await;
    my $test-result = verbose('Testing', @t.list>>.results>>.list.map({ ok => all($_>>.ok), module => $_>>.file.IO.basename }));


    # Send a build/test report
    if ?$report {
        my $report-promise = Promise.new;
        my $report-vow     = $report-promise.vow;
        my $report-await   = start { show-await("Uploading Test Reports", $report-promise) };
        my @r = $auth.report(
            @metas,
            test-results  => @t, 
            build-results => @b,
        );
        $report-vow.keep(1);
        await $report-await;
        verbose('Reporting', @r);
        print "===> Report{'s' if @r.elems > 1} can be seen shortly at:\n";
        print "\thttp://testers.perl6.org/reports/$_.html\n" for @r.grep(*.<id>).map({ $_.<id> });
    }


    print "Failed tests. Aborting.\n" and exit $test-result<nok> if $test-result<nok>;


    my $install-promise = Promise.new;
    my $install-vow     = $install-promise.vow;
    my $install-await   = start { show-await("Installing", $install-promise) };
    my @i = Zef::Installer.new.install: @metas;
    $install-vow.keep(1);
    await $install-await;
    verbose('Install', @i.grep({ !$_.<skipped> }));
    verbose('Skip (already installed!)', @i.grep({ ?$_.<skipped> }));


    # exit code = number of modules that failed the install process
    exit @modules.elems - @i.grep({ !$_<ok> }).elems;
}


#| Install local freshness
multi MAIN('local-install', *@modules) is export {
    say "NYI";
}


#! Download a single module and change into its directory
multi MAIN('look', $module, Bool :$v, :$save-to = $*SPEC.catdir($*CWD,time)) { 
    my $auth = Zef::Authority::P6C.new;
    my @g    = $auth.get: $module, :$save-to, :skip-depends;
    verbose('Fetching', @g);


    if @g.[0].<ok> {
        say "===> Shell-ing into directory: {@g.[0].<path>}";
        chdir @g.[0].<path>;
        shell(%*ENV<SHELL> // %*ENV<ComSpec>);
        exit 0 if $*CWD.IO.path eq @g.[0].<path>;
    }


    # Failed to get the module or change directories
    say "!!!> Failed to fetch module or change into the target directory...";
    exit 1;
}


#| Get the freshness
multi MAIN('get', *@modules, Bool :$v, :$save-to = $*TMPDIR, Bool :$skip-depends) is export {
    my $auth = Zef::Authority::P6C.new;
    my @g    = $auth.get: @modules, :$save-to, :$skip-depends;
    verbose('Fetching', @g);
    say $_.<path> for @g.grep({ $_.<ok> });
    exit @g.grep({ not $_.<ok> }).elems;
}


#| Build modules in cwd
multi MAIN('build', Bool :$v) is export { &MAIN('build', $*CWD) }
#| Build modules in the specified directory
multi MAIN('build', $path, Bool :$v, :$save-to) {
    my $builder = Zef::Builder.new;
    $builder.pre-compile($path, :$save-to);
}


# todo: non-exact matches on non-version fields
multi MAIN('search', Bool :$v, *@names, *%fields) {
    my $auth = Zef::Authority::P6C.new;
    $auth.update-projects;

    my @results = $auth.search(|@names, |%fields);
    say "===> Found " ~ @results.elems ~ " results";

    my @rows = @results.grep(*).map({ [
        "{state $id += 1}",
         $_.<name>, 
        ($_.<ver> // $_.<version> // '*'), 
        ($_.<description> // '')
    ] });
    @rows.unshift([<ID Package Version Description>]);

    my @widths     = _get_column_widths(@rows);
    my @fixed-rows = @rows.map({ _row2str(@widths, @$_) });
    my $width      = [+] _get_column_widths(@fixed-rows);
    my $sep        = '-' x $width;

    if @fixed-rows.end {
        say "{$sep}\n{@fixed-rows[0]}\n{$sep}";
        .say for @fixed-rows[1..*];
        say $sep;
    }

    exit ?@rows ?? 0 !! 1;
}


# returns formatted row
sub _row2str (@widths, @cells, :$max-width = $MAX-TERM-COLS) {
    # sprintf format
    my $format   = join(" | ", @widths.map({"%-{$_}s"}) );
    my $init-row = sprintf( $format, @cells.map({ $_ // '' }) ).substr(0, $max-width);
    my $row      = $init-row.chars >= $max-width ?? _widther($init-row) !! $init-row;

    return $row;
}


# Iterate over ([1,2,3],[2,3,4,5],[33,4,3,2]) to find the longest string in each column
sub _get_column_widths ( *@rows ) is export {
    return (0..@rows[0].elems-1).map( -> $col { reduce { max($^a, $^b)}, map { .chars }, @rows[*;$col]; } );
}


sub _widther($str is copy) {
    return ($str.substr(0,*-3) ~ '...') if $str.substr(*-1,1) ~~ /\S/;
    return ($str.substr(0,*-3) ~ '...') if $str.substr(*-2,1) ~~ /\S/;
    return ($str.substr(0,*-3) ~ '...') if $str.substr(*-3,1) ~~ /\S/;
    return $str;
}
