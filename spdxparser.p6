use Test;
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
    regex complex-expression:sym<WITH> { \s+ <( 'WITH' \s+ <license-exception-id> }
    regex complex-expression:sym<AND>  { \s+ <( 'AND'  \s+
    [ <paren-expression> | <compound-expression> | <simple-expression> ]
    }
    regex complex-expression:sym<OR>   { \s+ <( 'OR'   \s+ [ <simple-expression> | <paren-expression> | <compound-expression>  ]    }
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
my @list =
    'MIT AND (LGPL-2.1+ OR BSD-3-Clause)' => 12,
    '(MIT AND LGPL-2.1+) OR BSD-3-Clause' => 13,
    'MIT AND LGPL-2.1+' => 8,
    '(MIT AND GPL-1.0)' => 9,
    '(MIT WITH GPL)' => 7,
    'MIT' => 3,
;
for @list {
    my $parse = Grammar::SPDX::Expression.parse(.key);
    ok $parse, .key;
    is $parse.gist.lines.elems, .value, "{.key} .gist.lines >= {.value}";
}
my $thing;
Grammar::SPDX::Expression.parse('(MIT AND LGPL-2.1+) OR BSD-3-Clause').say;
Grammar::SPDX::Expression.parse('MIT AND GPL').say;
done-testing;
#ok $thing;
#Grammar::SPDX::Expression.parse('(MIT AND LGPL-2.1+) OR BSD-3-Clause').say;
#Grammar::SPDX::Expression.parse('MIT AND LGPL-2.1+').say;
