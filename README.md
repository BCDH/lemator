**LEMATOR** (< Serb. лематор < лемати, to thrash, beat up; pun intended) is a brute-force lemmatizer and disambiguator written for PowerShell.

It's a simple tool based on dictionary look-ups. It does no fancy morphological analysis. The function `Use-Lemmatizer` looks up tokens from a TEI XML file in a morphological lexicon and records all the possible lemmas for a given token (separated by '|' if the look-up was non-ambiguous) in the TEI XML output file:

![Скриншот 2019-11-16 11.30.10](https://i.imgur.com/lA7zApA.png)

The non-recognized tokens (i.e. those not present in the morphological lexicon) are logged by frequency so that they can be used to improve the morphological lexicon:

![Скриншот 2019-11-16 12.10.05](https://i.imgur.com/weddtP3.png)

In a second step, Lemator's `Use-Disambiguator` function can be used to manually disambiguate ambiguous lemmas (separated by '|') from a TEI XML file. To speed the process up, users can disambiguate multiple contexts at the same time:  

![Скриншот 2019-11-16 12.15.01](https://i.imgur.com/upIt7qy.jpg)

For details on how to use and configure Lemator, see below.


## Use-Lemmatizer

This function:
- collects all the words from the source xml file using a given XPATH (see variable `$XPATH_W` in `lemator.psm1`)
- looks up the lemma values in the dictionary file for each collected token
- records the lemma value(s) in an attribute for each token (see variable `$ATTR_LEMMA` in `lemator.psm1`)
- outputs the fully reconstructed, lemmatized XML file.

PARAMETER Source<br/>
Input XML, mandatory.

PARAMETER Target<br/>
Output file; optional; by default adds a suffix .lemmatized before the .xml suffix, so that
the input file `VSK.P13.sample.xml` will be saved as `VSK.P13-sample.lemmatized.xml`.

PARAMETER Type<br/>
- With type "AllLemmas", for a given word form, the lemmatizer will look up all possible lemmas in the dictionary file, reduce them to a unique list and record them like this "lemma1|lemma2|lemma3".
- With type "UniqueLemmas", the lemmatizer will record lemmas only for non-ambiguous tokens, i.e. only for those tokens that have exactly one possible lemma listed in the dictionary file.

PARAMETER Dictionary<br/>
Dictionary file, optional. Default value: "slaws.dic"

PARAMETER ProcessTagged<br/>
If enabled, the lemmatizer will process all the tokens from the xml source, regardless of their lemma attribute, otherwise it will skip word elements that already have a non-empty lemma attribute.

PARAMETER Unknown<br/>
Output text file (utf8) containing a sorted list of tokens without a corresponding dictionary-based lemma by their frequency.

EXAMPLE<br/>
```powershell
Use-Lemmatizer VSK.P13-sample.xml
```

EXAMPLE<br/>
```powershell
Use-Lemmatizer `
    -Source VSK.P13-sample.xml `
    -Target "$PSScriptRoot\.temp\result.xml" `
    -Dictionary "$PSScriptRoot\.temp\slaws.dic" `
    -Type UniqueLemmas
```

## Use-Disambiguator

The function:
- collects all tokens annotated with multiple lemmas (see `$XPATH_W` variable in `lemator.psm1` (for instance: `//tei:w[contains(@lemma, '|')]`) as well as their context (sentences, or words tokens and after)
- presents to the user a configurable number of sentences (contexts) in which the given multi-lemma combo appears and the option to chose which of the possible lemmas is appropriate in the given context
- outputs the fully reconstructed XML file containing only the disambiguated lemma value in the lemma attribute for each of the contexts

PARAMETER Source<br/>
Input XML, mandatory.

PARAMETER Target<br/>
Output file; optional; by default adds a suffix .disambiguated before the .xml suffix, so that the input file `VSK.P13.sample.xml` will be saved as `VSK.P13-sample.disambiguated.xml`.

PARAMETER Context<br/>
- With context "Sentence", the disambiguator will declare the context for each multilemma word to be a sentence, i.e. the `tei:s` node which is the parent of the  given `tei:w[contains(@lemma, '|')]`. Optional parameter. If the parameter is missing, the default is sentence.

- With context "Siblings", the disambiguator will declare the context for each multilemma combo to be a configurable number of siblings to the given `tei:w[contains(@lemma, '|')]` both on the left and right. This will be used for files that don't have explicit tags for sentences.

PARAMETER SiblingsNumber<br/>
This parameter is allowed only if we have `-Context Siblings`. The number indicates how many sibling-nodes (both on the left and the right) should be picked up by the script as the context for the given token.

PARAMETER ContextsPerWindow<br/>
This parameter indicates the number of contexts that the user will be considering at a time.
Default vlaue: 5.

EXAMPLE
```powershell
  Use-Disambiguator `
      -Source VSK.P13-sample.xml `
      -Context "Sentence" `
      -ContextsPerWindow 3
```
