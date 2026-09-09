<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>  -->

```
TITLE:     "ticfinder: Finding the Shape of Generated Prose"
FILE:      BLOG_tools_1_ticfinder.md
AUTHOR:    Jeff Nye
DATE:      2026-09-08
STATUS:    DRAFT
COPYRIGHT: "Copyright 2026 Jeff Nye"
```

<!--
---

::SERIES DESCRIPTION::
::BEGIN LINKS::
::END LINKS::
-->

# ticfinder: Finding the Shape of Generated Prose

## Abstract

<!-- ticfinder_off -->
ticfinder is a tool for identifying prose constructions common in LLM
generated text. I find that when editing the first draft of a document I
spend more time than I want tracking down LLM tics in order to rewrite
them. These tics are well known, beyond em-dashes: "it's not X, it's Y",
throat clearing, "an X wrapped in a Y trenchcoat", excessive use of
three-part phrases.
<!-- ticfinder_on -->

However ticfinder is not an AI-detector defeat tool.

The motivation for ticfinder is that these tics are distracting.
ticfinder helps me filter these distractions so I can assess whether my
specification or article is conveying the information accurately, and
putting the emphasis where I want it.

This is a common problem and there are several other tools in this vein,
with differences in approach. Some are built on top of Vale[1] and
supply style packages built on regular expressions. You may find these
useful, see [References](#references).

ticfinder parses markdown with spaCy[2] and reports the rhetorical
constructions that cluster in generated prose. Typical examples are three-part
coordination, corrective contrast, participial tails, and emphatic reflexives.

ticfinder reports raw counts and rates of occurrence, classifies what it
finds into named categories, and presents the result as a text report or
as simple HTML highlighting.

ticfinder supports a waiver mechanism. Findings you have read and accepted are
recorded there and drop out of later runs, so the reported count is becomes
those findings no one has looked at yet.

What follows is how the detection works, what a parse finds that a
regular expression cannot, what the neighbouring tools cover that this
one does not, and a short list of what is genuinely new here.

## Why this exists

The previous posts in the Pacino series concern LLM-based Co-design of
RTL. The methodology in RTL generation uses an LLM to draft RTL from a
task file. The designer reviews this RTL against planning documents. The
record of this review is captured in the task file. The documented
review and the unit test suites provide a preliminary level of trust in
the RTL outcome.

Pacino's next output is specification and documentation for human
readers, drafted by the same method. Detailed microarchitecture
specifications run to volume, which is what makes a prose style linter
like ticfinder worth having.

The problem is recognized, and growing. A study[3] of 28,415 PubMed
abstracts found LLM-associated marker use rising from 4.995 to 11.658
per thousand words after 2022, a 133% increase, while control vocabulary
declined. A separate study[4] identified 280 excess style words in
published scientific text. Both studies count words.

Counting structures is newer. DependencyAI[5], published February 2026,
detects AI-generated text from dependency relation labels alone,
deliberately discarding lexical markers, and reports that syntactic
structure carries the signal. Rallapalli et al.[6] scored
467,985 texts on Biber's sixty-seven lexicogrammatical features and
found past participial clauses among the five features LLMs most
overuse, which is `PARTICIPIAL_TAIL` under its linguistics name. The
constructions in this post are register markers that linguistics has had
vocabulary for since 1988, produced at rates a human register does not.
That is the premise ticfinder works from, turned to a different end. The
research classifies documents. This tool marks sentences for an editor.

## What it reports

A run prints a header, a count table, and the findings grouped by
construction.

```
BLOG_bpu_14_directed_validation.md
  5059 words - 316 sentences - 0 findings (0.0 per 1k words)
  22 waived - 1 region skipped via ticfinder_off
  clean
```

Constructions come in two tiers. Structural ones are functions over a
dependency parse: `CORRECTIVE_CONTRAST`, `NEG_ESCALATION`,
`ABSTRACT_ADVERB`, `EMPHATIC_REFLEXIVE`, `PARTICIPIAL_TAIL`,
`TRICOLON`, `DISGUISE_METAPHOR`, `ALTERNATIVE_FRAMING`. Lexical ones
are token patterns and word lists: `FRAME_MARKER`, `HOLLOW_BOOSTER`,
`CLOSER`, `EM_DASH`, `HEDGE_STACK`, and the phrase groups carried in a
JSON file.

The tiers are not equal partners. The structural detectors account for
the large majority of findings on the documents I have run, and the word
lists catch diction a parse cannot see, because no syntactic relation
distinguishes "delve" from "examine". That division is the ordinary
shape of register analysis, which has counted lexical items and
grammatical structures side by side since Biber[7] set out the
method in 1988. The lexical tier here is lemma-aware rather than
string-aware -- `leverage` reaches `leveraged` and `leveraging` through
lemmatisation -- and it is otherwise the same technique every tool in
this space uses. There is no claim attached to it.

What the parse buys is a different level of representation. The tool
reads syntactic relations rather than character sequences, and its unit
is a sentence from a segmenter, where the others work on a line or on a
document flattened to one string. Every claim in this post about what
ticfinder can see that the others cannot reduces to that, and nothing
about it requires the word lists to be clever.

The split that matters is not structural versus phrasal. It is
construction versus pattern. A construction is a rhetorical move with a
stable id. A pattern is one executable query that finds one of its
surface forms. `CORRECTIVE_CONTRAST` owns several patterns, because the
same move parses several ways: coordinated with "but", a two-clause
cleft including one that spans a sentence boundary, asyndetic sibling
phrases, negated apposition. "rather than", "instead of" and "less X
than Y" sit under `ALTERNATIVE_FRAMING` instead, on base rate.

A pattern can carry its own confidence and override the construction's,
because base rates inside one rhetorical family vary enormously. `not X
but Y` is rare and diagnostic. A bare `rather than` is ordinary English
describing a real choice. Reporting them at equal confidence makes the
good rules look unreliable. That is also why "rather than" lives under
`ALTERNATIVE_FRAMING` and not `CORRECTIVE_CONTRAST`: same rhetorical
family, completely different base rate. Group ids by precision, not by
rhetorical neatness.

## A worked case

The previous post in the BPU series, on directed validation, went
through ticfinder before publication. Working one construction at a
time, highest count first, the pass ended with every finding either
rewritten or waived.

Two constructions came out entirely, with nothing waived.
`PARTICIPIAL_TAIL` was the clearest tic in the document and every one
became a main clause. Every `EMPHATIC_REFLEXIVE` went too, because in
each case dropping "itself" cost nothing.

What was waived is more informative. Most of the tricolons were real
lists: "The epoch, target, allocation, aging and prediction-side paths
had not" enumerates five paths, and "primary update, alternate update,
and allocation" names three buses in a sentence whose subject is that
there are three of them. Every corrective contrast survived the tool's
own test -- was X actually claimed by someone? -- because the document
had spent a section establishing X in each case. Most of the
alternative framing survived too, which is the base-rate problem in the
open.

Two domain terms tripped detectors on their own. `mutually exclusive`
reads as `ABSTRACT_ADVERB` and `by construction` as `BORROWED_RIGOUR`.
In a hardware document both mean exactly what they say -- the second one
does real work: it marks a claim proven by the structure of an
expression, not by a test, which is the distinction that post was about.

Two failure modes are worth recording because both cost rework.

Rewrites introduce findings. Splitting a participial tail promotes
whatever the tail carried into a main clause, and a three-item list
there becomes a tricolon. The total fell while a new finding appeared.
Compare the finding set between runs, not the count.

Masked text misleads. Markdown masking blanks inline code while
preserving offsets, so line numbers stay right and the quoted text goes
wrong. One finding reads "reverted a TAGE epoch gate to alone" for a
source line ending in an inline `prm_match`. Judge from the source
line, never from the quote.

## The ledger

Each finding carries a six-character id that hashes the construction,
the pattern, the matched text and the containing sentence, with
whitespace normalised and offsets excluded. Rewrapping a paragraph
keeps the waiver. Rewriting the sentence retires it.

After review, the remaining findings are waived by id, and the waiver
file records what was accepted and why it was recognisable six months
later. The reported count is then the number of findings nobody has
looked at yet. Zero means reviewed, not clean, and those are different
claims. A file with an empty waiver object says the document was
reviewed and nothing was waived. A missing file says it was never
reviewed at all.

Waivers whose text has vanished report as stale instead of accumulating
silently. A clean count sitting on stale entries is a false green, and
that is the same class of error as a status count carried forward from a
run nobody made -- the failure the previous post was written about.

The practical consequence is an ordering rule. Because an id covers the
sentence containing the match, rewriting a sentence retires any waiver
written against it, so waiving as you go leaves stale entries behind.
Work the document first, then take the waive list from one clean run at
the end.

## The neighbours

Prose linting is old. proselint[8] carries 70-plus checks and matches
against dictionaries and regular expressions; the diacritical-marks
check is a straight lookup table. write-good[9] calls itself a naive
linter and builds regexes. Vale has twelve rule extension points, of
which exactly one, `sequence`, touches linguistics at all, reading
part-of-speech tags a sentence at a time. None of the three parses.

Closer to home, there is a cluster of Vale style packages aimed
squarely at LLM prose, and they got there independently.

| project | scale | detection |
|---|---|---|
| vale-ai-tells[10] | largest, well over a hundred rules | overwhelmingly `existence`, a handful of `script` and `sequence` |
| deslop[11] | a few dozen rules | `existence`, `occurrence`, `substitution` |
| vale-llm-slop[12] | a couple of dozen rules | `existence`, with some `sequence` |
| slopster[13] | a handful, plus an agent skill and a diff tool | `existence`, `substitution` |
| ticfinder[14] | a dozen constructions and a phrase file | dependency parse plus token matcher |

Rule counts move whenever those repositories move, so the table gives
the shape rather than a census. The proportions are the durable part: in
the largest of them, the overwhelming majority of rules are `existence`,
which is regex.

The taxonomies converge to a degree that is hard to dismiss. deslop has
a rule named `BorrowedRigor`; I have a construction named
`BORROWED_RIGOUR`, and neither of us knew about the other. deslop's
`AntitheticalPair`, vale-llm-slop's `NegativeParallelism`,
vale-ai-tells' `ContrastiveNegation` and my `CORRECTIVE_CONTRAST` are
one construction under four names. `HedgeCascade` is `HEDGE_STACK`.
`HollowCloser` is `CLOSER`. `OpenerCliche` is `FRAME_MARKER`. All five
projects have an em-dash rule.

None of this was coordinated. Four of the five projects were published
before I knew any of them existed, and the overlap lies in which
constructions they name; the rule wording differs everywhere.

## Regex against a parse

The clearest comparison available is the tricolon, because
vale-ai-tells and ticfinder both detect it and the implementations
could not be less alike.

vale-ai-tells uses a couple of dozen hand-written regular expressions:
gerund, past tense, third person, base form after a modal, base form
after a pronoun subject, shared infinitive, repeated infinitive and
post-colon, each crossed with syndetic and asyndetic forms and with
"and" against "or", plus a negative lookbehind that exempts Conventional
Commits subjects. The file's own comment explains the hardest part:

> Vale flattens a document to a single string before matching, joining
> paragraphs with spaces, so a gap that allowed a period would let three
> clauses drawn from three separate sentences read as a series. That is
> how a slop paragraph of six short sentences used to report a tricolon
> it never contained.

That failure mode does not exist over a parse. A dependency tree knows
where the sentence ends and which tokens are conjuncts of which head,
so three-part coordination is one detector, and it reports whether the
coordination is of verbs, nouns or auxiliaries as a subtype rather than
as a separate rule. The same holds for corrective contrast:
vale-ai-tells' `ContrastiveNegation` is two regexes whose comment
concedes it "will also catch a literal 'coffee, no sugar'".

The Vale packages are not unlinguistic. Their `sequence` rules read
part-of-speech tags, and word lists are lexicography. What Vale fixes
for its rulesets is the level of representation, and that is the whole
of the difference. Its only linguistic extension point reads
part-of-speech tags, so a rule that needs to know what is coordinated
with what has to enumerate surface forms. Given that constraint,
twenty-four regexes and a lookbehind is good engineering.

The cost of the parse is the opposite one. spaCy's `md` model is a
dependency on every run, parse quality is the ceiling on precision, and
where the parse is wrong the finding is wrong. Masked inline code
degrades the parse locally, which is why the quoted text misleads.

## What is actually new

Very little, and it is worth being specific about which little.

Not new: prose linting. Not new: flagging LLM constructions -- four
other projects, one with ten times the rule count. Not new: the insight
that structure beats vocabulary as a signal, which the detection
literature reached first and tested properly. Not new: content-hash
suppression, which is standard practice in code analysis[15], where
Psalm, Android Lint, PVS-Studio, detekt, SonarQube and Semgrep all hash
warning fields precisely because line numbers shift.

What appears to be uncommon, in descending order of confidence:

Detection at the level of syntactic structure rather than surface form,
in a tool meant for editing. The detection research parses; the editing
tools match surface forms. ticfinder sits in between. The tricolon
labelling is the clearest case: deciding whether three coordinated nouns
are a rhetorical figure or an ordinary list draws on item count,
determiners, premodifiers, a cue word in the lead-in, and whether the
members are short and of similar length. That is not a question a
surface-form matcher answers badly. It is a question it cannot ask.

The construction-and-pattern hierarchy, with per-pattern confidence
overriding the construction's. The Vale rulesets are flat, and
vale-ai-tells sets every rule to `error`. Owning several patterns under
one stable id is what lets the id survive when surface forms drift, and
what lets one noisy pattern be muted without losing the construction.

A persistent review ledger for prose. None of the four has one.
slopster's `slop-diff` comes nearest. It compares a branch against main
and reports only new findings, and it is immune to line shifts. But that
answers what changed, not what a human has accepted. For a specification
that will be reviewed repeatedly by different people, the second
question is the one that matters.

One caveat sits under all four. None of this is validated. There is no
corpus study behind ticfinder, no precision or recall figure, and no
baseline beyond my own documents. The same is true of every tool named
here, but a claim about levels of representation invites the question,
and the honest answer is that the evidence in this post is worked
examples rather than measurement.

Refusing to render a verdict. ticfinder reports a rate against a
denominator the author controls, and states in its own documentation
that every construction it finds is legitimate English. That is a
design stance rather than a feature, and it is the reason the tool is
usable on a document where six of eight `ALTERNATIVE_FRAMING` hits are
correct.

## What I am taking from the others

Reading four competing implementations produced a longer list of things
to add than of things to claim.

The largest gap is a category, not a rule. vale-ai-tells measures
sentence-length variance, paragraph-length variance, sentence-start
entropy, sentence-start repetition, transition repetition and content
duplication, in Tengo scripts that section a document by heading first.
The signal there is the absence of variance rather than the presence of
a construction, it is the best-supported signal in the stylometry
literature, and ticfinder does not look for it at all. It already
computes the sentence statistics and reports them in its JSON output;
nothing reads them.

After that: anthropomorphism rules, which matter more for hardware
documentation than for prose style, since "the module wants to" is a
precision defect before it is a tell. Chat-artifact tells --
assistant openers and closers, sycophancy, performed candor -- which
leak whenever an assistant drafts specification text. Heading rules,
of which vale-ai-tells has six and ticfinder none. And a set of
constructions the Vale packages implement as regex that would suit a
parse better: pseudo-cleft, shell-noun copula, summative appositive,
stacked anaphora.

The most immediately useful is the least sophisticated. vale-ai-tells
disables its fall-metaphor rules for aviation prose. I have been hand-
waiving `mutually exclusive` and `by construction` on every hardware
document, which is a domain vocabulary problem with a known solution.


## Where this goes

The BPU posts argued that a test which has only ever run against
conforming RTL has unknown detection capability, and that the cheap fix
is to break the design, watch the test fail, and put it back. The
prose analogue is weaker but the same shape: a construction that has
only ever been read by its author has unknown load-bearing capacity,
and the cheap fix is to try the sentence without it.

The tool does not do that. It cannot, and it should not pretend to. It
narrows five thousand words to twenty-two decisions and keeps the
record of how they went. That is the same division of labour as the RTL
work, and it is the reason the tool is now in the loop for Pacino's
documentation rather than only for these posts.

---

## References

<!-- ticfinder_off -->
[1] Vale: A Syntax-Aware Linter for Prose. Errata AI, github.com/errata-ai/vale.
Accessed 8 Sept. 2026.

[2] Honnibal, Matthew, et al. spaCy: Industrial-Strength Natural Language
Processing in Python. Zenodo, 2020, https://doi.org/10.5281/zenodo.1212303.

[3] Alani, Noor H. S., Jansen, Bernard J., "Are Scientists Starting to Sound
like ChatGPT? Stylistic Diffusion in Biomedical Abstracts in the LLM Era."
Machine Learning and Knowledge Extraction, vol. 8, no. 8, 2026,
https://doi.org/10.3390/make8080223.

[4] Kobak, Dmitry, et al. "Delving into ChatGPT Usage in Academic Writing
through Excess Vocabulary." arXiv, 2024, arxiv.org/abs/2406.07016.

[5] Ahmed, Sara, and Tracy Hammond. "DependencyAI: Detecting AI Generated Text
through Dependency Parsing." arXiv, 2026, arxiv.org/abs/2602.15514.

[6] Rallapalli, Swati, et al. "Interpretable Stylistic Variation in Human and
LLM Writing across Genres, Models, and Decoding Strategies." arXiv, 2026,
arxiv.org/abs/2604.14111.

[7] Biber, Douglas. Variation across Speech and Writing. Cambridge UP, 1988.

[8] Pacer, Michael D., and Jordan W. Suchow. "Linting Science Prose and the
Science of Prose Linting." Proceedings of the 15th Python in Science
Conference, 2016.

[9] Ford, Brian. write-good: Naive Linter for English Prose. 2018,
github.com/btford/write-good. Accessed 8 Sept. 2026.

[10] Bailey, Tim. vale-ai-tells: A Vale Style Package for AI Tells.
github.com/tbhb/vale-ai-tells. Accessed 8 Sept. 2026.

[11] Miller, J. deslop: A Vale Style Package That Flags AI-Slop in Prose.
github.com/JMill/deslop. Accessed 8 Sept. 2026.

[12] vale-llm-slop: Vale Styles That Lint Your Prose.
github.com/Syntaf/vale-llm-slop. Accessed 8 Sept. 2026.

[13] Harris, Todd. slopster: Catch AI Slop in Your Writing before You Publish
It. github.com/t0ddharris/slopster. Accessed 8 Sept. 2026.

[14] Nye, Jeff. ticfinder. uarchlabs, github.com/uarchlabs/ticfinder. Accessed
8 Sept. 2026.

[15] Karpov, Andrey. "Static Analysis: Baseline VS Diff." PVS-Studio, 2020,
habr.com/en/companies/pvs-studio/articles/513952/.

## See Also

Alex Contributors. alex: Catch Insensitive, Inconsiderate Writing. 2015,
github.com/get-alex/alex. Accessed 8 Sept. 2026.

Park, Kyumin, et al. "RedPen: Region- and Reason-Annotated Dataset of Unnatural
Speech." arXiv, 2022, arxiv.org/abs/2210.14406.

Perin, Fabrizio, Lukas Renggli, and Jorge Ressia. "Linguistic Style Checking
with Program Checking Tools." Computer Languages, Systems & Structures, vol.
38, no. 1, 2012, pp. 61-72.

Sun, Mingjie, et al. "Idiosyncrasies in Large Language Models." arXiv, 2025,
arxiv.org/abs/2502.12150.

Wikipedia Contributors. "Wikipedia: Signs of AI Writing." Wikipedia,
en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing. Accessed 8 Sept. 2026.
<!-- ticfinder_on -->

---

<!-- ticfinder_off -->
*Jeff Nye is a microprocessor architect with 35 years of industry
experience spanning performance modeling, RTL implementation, and
architecture for high-performance OOO processors. He has contributed RTL
to Pentium 4, Arm v7, TI C6x and RISC-V designs, and recently served as
sole architect and full-stack implementer of the TAGE-SC-L + ITTAGE
branch prediction cluster in an 8-issue RVA23 RISC-V processor, from
research through timing closure at 2.75 GHz. He holds more than 20
issued patents in processor design, architecture, and hardware
virtualization. He is the author of Pacino and the uarchlabs methodology
documented here.*

*Connect on [LinkedIn](https://www.linkedin.com/in/jeff-nye-21353926).*
<!-- ticfinder_on -->
