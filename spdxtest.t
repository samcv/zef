use Test;
use lib 'lib';
use spdxparser;
my @list =
    'MIT AND (LGPL-2.1+ OR BSD-3-Clause)' => 12,
    '(MIT AND LGPL-2.1+) OR BSD-3-Clause' => 12,
    'MIT AND LGPL-2.1+' => 7,
    '(MIT AND GPL-1.0)' => 8,
    '(MIT WITH GPL)' => 7,
    'MIT' => 3,
    'GPL-3.0 WITH Madeup-exception' => 6
;
my @blacklist = 'a';
my @lics = 'a', 'b', 'c';
say so @lics.any eq @blacklist.any;
my $res = Grammar::SPDX::Expression.parse(@list[2].key, actions => parsething.new);
say '===========';
say $res;
$res .= made;
say $res.perl;
is-deeply
    Grammar::SPDX::Expression.parse(
        @list[2].key,
        actions => parsething.new
        ).made,
    ${:exceptions($[]), :!is-simple, :licenses($[["MIT", "LGPL-2.1+"],])}
;

#for @$res {
#    .say
#}

exit;
for @list {
    my $parse = Grammar::SPDX::Expression.parse(.key, :actions(parsething.new));
    ok $parse, .key;
    is $parse.gist.lines.elems, .value, "{.key} .gist.lines >= {.value}";
}
my $thing;
done-testing;
