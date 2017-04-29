use Test;
grammar Grammar::SPDX::Expression {
    regex TOP { \s*
        <compound-expression> \s*    }

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
    regex complex-expression:sym<AND>  { \s+ <( 'AND'  \s+ <compound-expression>    }
    regex complex-expression:sym<OR>   { \s+ <( 'OR'   \s+ <compound-expression>    }
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
    'MIT AND (LGPL-2.1+ OR BSD-3-Clause)',
    '(MIT AND LGPL-2.1+) OR BSD-3-Clause',
    'MIT AND LGPL-2.1+',
    '(MIT AND GPL-1.0)',
    '(MIT WITH GPL)',
    'MIT'
;
for @list {
    ok Grammar::SPDX::Expression.parse($_), $_;
}
my $thing = Grammar::SPDX::Expression.parse('MIT AND (LGPL-2.1+ OR BSD-3-Clause)');
say $thing;
done-testing;
#ok $thing;
#Grammar::SPDX::Expression.parse('(MIT AND LGPL-2.1+) OR BSD-3-Clause').say;
#Grammar::SPDX::Expression.parse('MIT AND LGPL-2.1+').say;
