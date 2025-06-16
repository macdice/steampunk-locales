# steampunk-locales

glibc 2.35 introduced C.UTF-8, whose LC\_COLLATE definition simply says:

```
LC_COLLATE
% The keyword 'codepoint_collation' in any part of any LC_COLLATE
% immediately discards all collation information and causes the
% locale to use strcmp/wcscmp for collation comparison.  This is
% exactly what is needed for C (ASCII) or C.UTF-8.
codepoint_collation
END LC_COLLATE
```

That works the same as C.UTF-8 on FreeBSD and probably other systems, and has
the obvious meaning that text is sorted in codepoint order, which also matches
UTF-8 binary order, ie memcmp() order.  Before that, Debian (and Ubuntu, ...)
systems carried a local patch to add C.UTF-8 that was not from the glibc
project.  It produces a strange sort order, probably due to implementation
limitations or artefacts.  That is, glibc does not actually respect the
definition, which asks for codepoint order.

The goal of this exercise is to see if I can produce a custom locale definition
that can be compiled on modern glibc to give that strange sort order from old
Debian systems for C.UTF-8.  This might be temporarily useful when moving a
PostgreSQL database index from and old Debian system to a new system,
preserving the sort order until the user is ready to move to true Unicode
codepoint order (ie rebuild the indexes).

I do not wish to study glibc internals, so I am studying observable external
behaviour only.  We can see that Debian defines the sort order as literally
numerical code point order, as expected:

```
LC_COLLATE
order_start forward
<U0000>
..
<U007F>
<U0080>
..
<U00FF>
<U0100>
..
<U017F>
<U0180>
..
<U024F>
<U0250>
..
....etc...
..
<UE01EF>
<UF0000>
..
<UFFFFF>
<U100000>
..
<U10FFFF>
UNDEFINED
order_end
END LC_COLLATE
```

I don't know why it was expressed as a series of small ranges at the start
and long ranges at the end.

Surprisingly, when you sort a UTF-8 file containing every codepoint separated
by line breaks on Debian 11 (glibc 2.31), the resulting order has some ranges
that are *not* ordered by code point and thus do not follow the definition.  It
is ordered correctly for large ranges of codepoints, but appears to jump
around, including right at the beginning:

```
<U0000>
<U0001>
<U0378>
<U0379>
<U0380>
<U0381>
<U0382>
<U0383>
<U038B>
<U038D>
...
```

I will assume for now that it still has the transitive property and I have not
yet seen any evidience that it doesn't; that is strictly required for use in
indexes.  (If it doesn't, then Debian's old C.UTF-8 is not worth thinking about
any further and we should just be glad it is obsolete; this exercise is
predicated on the assumption that it does and it is a reasonable goal to try
to provide an upgrade path.)

One observation is that Debian's definition lists points that are not defined
by Unicode and are not in the accompaning UTF-8 charmap definition (probably
not strictly allowed by POSIX).  They may be sorted as UNDEFINED, but this
doesn't seem to be enought to explain the observed jumps.  Another is that the
locale definition uses notation like `<U10FFFF>` for values above ffff (as if
formatted with `%04X` in printf, so at least four digits and then extra digits
only if required), while the charmap uses `<UFFFF>` but `<U0010FFFF>`, ie
`%04X` for the basic multilingual plane and `%08X` for larger values.  This may
be causing all codepoints outside the BMP to be sorted as UNDEFINED, though
it's not yet clear to me.

Attempt 1

I made a file containing all possible codepoints (even undefined ones) from
`<U0000>` to `<U10FFFF>`:

```
$ cat print-all-codepoints.py 
for i in range(0, 0x10ffff + 1):
    if i >= 0xd800 and i <= 0xdfff:
        continue # skip UTF-16 surrogates, which have no valid encoding in UTF-8
    print(chr(i))
$ python3 ./print-all-codepoints.py > codepoints.txt
```

I sorted this on a Debian 11 system:

```
vagrant@bullseye:~$ LC_ALL=C.UTF-8 sort < codepoints.txt > sorted-old.txt
vagrant@bullseye:~$ head -10 sorted-old.txt | python3 show-codepoints.py 


<U0000>
<U0001>
<U0378>
<U0379>
<U0380>
<U0381>
<U0382>
<U0383>
...
```

I 

  The goal
here is to produce a modern locale definition that produces bug-compatible

Attempt 1:

Since I do not wish to study the glibc code and want to work only with the
POSIX standard and observable behaviour, I first tried sorting a file
containing all Unicode code points 0-10ffff, without worrying whether they were
defined or not, and used that to build a replacement LC\_COLLATE definition
that matches the order produce by "sort".  (Unlike more complicated locales
that have weightings and more complex multi-character behaviour, C.UTF-8 should
by definition be testable by sorting strings consisting of just one code
point.)

An initial observation was that the sort order absolutely doesn't match the the
order described in the "C" file: for whatever internal reason, various ranges
are scambled.  Baffling, but OK, I was capturing what it actually did, not what
the defintion said it should do, over the total set of possible codepoints.

That almost worked perfectly, but revealed a problem with around 50 codepoints.
On closer inspection, glibc 2.31 in Debian bullseye doesn't seem to consider
characters ranges covered by /usr/share/i18n/locales/C as undefined even if
they are not listed in the charmap file for UTF-8, so for example U085F
(undefined by Unicode, but listed in the bullseye "C" file) was considered to
precede U0860, while glibc 2.41 in Debian trixie correctly considers it to be
undefined because "UTF-8" didn't list it, and thus sorts it in the position of
UNDEFINED in the "C" file, and thus after all defined codepoints.  These 50
or so code points moved to the end if "C" was compiled by the newer localedef
program and "sort" was run with that locale in the newer glibc.

Attempt 2:

In order to make the newer glibc treat undefined characters as defined, I tried
marking them as defined, by building a new charmap file "UTF-8" that worked
backwards from the codepoints defined by the older glibc "C" locale definition,
instead of using the older "UTF-8" charmap.

The resulting C file can be compiled with newer localedef using the UTF-8
charmap from the old system, to produce a locale that sorts the same way as
Debian bullseye and probably older systems.  This way you can get
bug-compatible old-Debian C.UTF-8 sorting on a system that is running modern
glibc.

Problems still to be resolved:

* a small number of characters seems to be sorted as UDEFINED (at the end)
  with new localedef/glibc, but in a different position in 
