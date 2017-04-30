grammar Grammar::SPDX::Expression {
    regex TOP {
        \s*
        | <paren-expression>
        | <simple-expression>
        | <compound-expression>

        \s*
    }

    regex idstring { [<.alpha> | <.digit> | '-' | '.']+ }

    regex license-id { <.idstring> }

    regex license-exception-id { <.idstring> }

    regex license-ref { ['DocumentRef-' <.idstring> ':']? 'LicenseRef-' <.idstring> }

    regex simple-expression {
        | <license-id> '+'?
        | <license-ref>
    }
    proto token complex-expression { * }
    regex complex-expression:sym<WITH> {
        \s+ <(
        'WITH' \s+
        <license-exception-id>
    }
    regex complex-expression:sym<AND>  {
        \s+ <(
        'AND'  \s+
        [ <simple-expression> | <paren-expression> | <compound-expression> ]
    }
    regex complex-expression:sym<OR>   {
        \s+ <(
        'OR'   \s+
        [ <simple-expression> | <paren-expression> | <compound-expression>  ]
    }
    regex paren-expression {
        '(' <compound-expression> ')'
    }
    regex compound-expression {
        [
          | <paren-expression>
          | <simple-expression>
        ]
        [ <complex-expression>+ ]?
    }
}
class parsething {
    has @!licenses;
    has @!exceptions;
    has @!compound;
    has @!stack;
    my $no = 0;
    has Bool:D $.is-simple = True;
    method TOP ($/) {
        make {
            licenses => @!licenses,
            is-simple => $!is-simple,
            exceptions => @!exceptions
        }
    }
    method simple-expression ($/) {
        $/.make: ~$<license-id>;
        @!stack.push:    ~$<license-id>;
        #@!licenses.push: ~$<license-id>;
    }
    method complex-expression ($/) {
        $!is-simple = False;
    }
    method complex-expression:sym<AND> ($/) {
        self.complex-expression($/);
        #shift off the stack of the last simple-expression
        self.push-license: self.shift-stack;
        if $<paren-expression> {
            say "oh no parens. make sure to keep all of it!";
            # dump the stack. we don't need information about the next thing
            # because it is AND so we know these licenses are not in relation to
            # each other.
        }
        elsif $<simple-expression> {
            self.push-license(~$<simple-expression>);
        }
        say $/;
    }
    method complex-expression:sym<WITH> ($/) {
        self.complex-expression($/);
        @!exceptions.push: $/.make: ~$<license-exception-id>;
    }
    method complex-expression:sym<OR> ($/) {
        self.complex-expression($/);
        @!exceptions.push: $/.make: ~$<license-exception-id>;
    }
    method shift-stack {
        my $item = @!stack.shift;
        say "shifting the stack of $item";
        $item;
    }
    method push-license ($item) {
        say "pushing $item to license array";
        if @!licenses.elems {
            say @!licenses.perl;
            @!licenses[*-1].push: $item;
        }
        else {
            @!licenses[0] = [$item, ];
        }
    }

}
