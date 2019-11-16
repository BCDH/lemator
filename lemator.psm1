$script:WORD_COLOR=[System.ConsoleColor]::Red

try {
    [Reflection.Assembly]::LoadWithPartialName("System.Xml.Linq") | Out-Null
} catch {

}

function ReadInputChar {
    Param(
        [char[]]$Valid,
        [char]$Min,
        [char]$Max
    )

    $q = Read-Host

    if ($q.Length -eq 0) {
        Exit
    }

    $q = [char]::ToLower($q[0])
    if ($Valid) { $Valid = $Valid | %{ [char]::ToLower($_) } }
    if ($Min) { $Min = [char]::ToLower($Min) }
    if ($Max) { $Max = [char]::ToLower($Max) }
    $error = `
        ($Valid -and ($q -notin $Valid)) `
        -or ($Min -and ($q -lt $Min)) `
        -or ($Max -and ($q -gt $Max))

    if (-not $error) {
        $q
    }
}

# Converts strings like 1,2,6-10,15,20 into array of integers
function IntArrayFromString {
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Value
    )

    [int[]]$result = @()

    $Value.Split(",") | %{
        $range = $_.Split('-')
        if ($range.Length -eq 1) {
            $result = $result + [int]$range[0]
        } elseif ($range.Length -eq 2) {
            $min = [int]$range[0]
            $max = [int]$range[1]
            $result = $result + $min..$max
        }
    }

    $result
}

function ResolvePath($path) {
    if ([System.IO.Path]::IsPathRooted($path)) {
        $path
    } else {
        Join-Path -Path (Get-Location) -ChildPath $path -Resolve
    }
}

# Load dictionary into hashtable.
# The dictionary should contain a comma separated list of tokens and lemmas, one token per line
function LoadDictionary($path) {
    $file = Join-Path -Path (Get-Location) -ChildPath $path -Resolve
    $reader = [System.IO.File]::OpenText($file)

    $result = @{}
    while($null -ne ($line = $reader.ReadLine())) {
        $parts = $line.Split(",")

        $lemmas = $result[$parts[0]]
        if (-not $lemmas) {
            $lemmas = @($parts[1])
        } else {
            $lemmas = $lemmas + @($parts[1])
        }

        $result[$parts[0]] = $lemmas
    }

    $reader.Dispose()

    $result
}

function CreateXmlReader($source) {
    $settings = New-Object -TypeName System.Xml.XmlReaderSettings
    $settings.IgnoreWhitespace = $false
    $reader = [System.Xml.XmlReader]::Create($source, $settings)
    [System.Xml.Linq.XDocument]$xml = [System.Xml.Linq.XDocument]::Load($reader)
    $nt = New-Object -TypeName System.Xml.NameTable
    $ns = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $nt
    $ns.AddNamespace("tei", "http://www.tei-c.org/ns/1.0");
}

<#

    .SYNOPSIS
    Lemator (< Serb. лематор) is a simple dictionary-based lemmatizer. Cmdlet parses an xml file, lemmatizes it (assigns dicitonary-keyword forms to tokens by looking them up in a dictionary file; and outputs a new XML file with @lemma attributes in it.

    .DESCRIPTION
    The lemmatizer functions by:
    - collecting all the words from the source xml file using a given XPATH (see the variable $XPATH_W below)
    - looking up the lemma values in the dictionary file for each collected token
    - recording the lemma value(s) in an attribute for each token (see variable $ATTR_LEMMA below)
    - Outputting the fully reconstructed, lemmatized XML file.

    .PARAMETER Source
    Input XML, mandatory.

    .PARAMETER Target
    Output file; optional; by default adds a suffix .lemmatized before the .xml suffix, so that
    the input file `VSK.P13.sample.xml` will be saved as `VSK.P13-sample.lemmatized.xml`.

    .PARAMETER Type
    With type "AllLemmas", for a given word form, the lemmatizer will look up all possible in the dictionary file, reduce them to a unique list and record them like this "lemma1|lemma2|lemma3".
    With type "UniqueLemmas", the lemmatizer will record lemmas only for non-ambiguous tokens, i.e. only for those tokens that have exactly one possible lemma listed in the dictionary file.

    .PARAMETER Dictionary
    Dictionary file, optional. Default value: "slaws.dic"

    .PARAMETER ProcessTagged
    If enabled, the lemmatizer will process all the tokens from the xml source, regardless of their lemma attribute, otherwise it will skip word elements that already have a non-empty lemma attribute.

    .PARAMETER Unknown
    Output text file (utf8) containing a sorted list of tokens without a corresponding dictionary-based lemma by their frequency.

    .EXAMPLE
    Use-Lemmatizer VSK.P13-sample.xml

    .EXAMPLE
    Use-Lemmatizer `
        -Source VSK.P13-sample.xml `
        -Target "$PSScriptRoot\.temp\result.xml" `
        -Dictionary "$PSScriptRoot\.temp\slaws.dic" `
        -Type UniqueLemmas

#>
function Use-Lemmatizer {
    Param
    (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Source,

        [Parameter(Mandatory = $false, Position = 1)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [ValidateSet("UniqueLemmas", "AllLemmas")]
        [string]$Type,

        [Parameter()]
        [string]$Dictionary = "slaws.dic",

        [Parameter()]
        [switch]$ProcessTagged = $false,

        [Parameter()]
        [string]$Unknown
    )

    $ATTR_LEMMA = "lemma"
    $XPATH_W = "//tei:w[@xml:id][ancestor::tei:div[@xml:lang='sr']]"
    if (-not (Test-Path $Source)) {
        throw "Source file <$Source> not found."
    }

    if (-not (Test-Path $Dictionary)) {
        throw "Dictionary file <$Dictionary> not found."
    }

    # If there is no target file defined, we use source file name with ".lemmatized"
    # suffix (before file extension).
    if (-not $Target) {
        $path = [System.IO.FileInfo](Resolve-Path $Source).Path
        $Target = "$($path.DirectoryName)\$($path.BaseName).lemmatized$($path.Extension)"
    }

    $dict = LoadDictionary $Dictionary
    $unknowns = @{}

    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    #$Source = ResolvePath $Source
    #$Target = ResolvePath $Target

    $readerSettings = New-Object -TypeName System.Xml.XmlReaderSettings
    $readerSettings.IgnoreWhitespace = $false
    $reader = [System.Xml.XmlReader]::Create($Source, $readerSettings)
    [System.Xml.Linq.XDocument]$xml = [System.Xml.Linq.XDocument]::Load($reader)
    $nt = New-Object -TypeName System.Xml.NameTable
    $ns = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $nt
    $ns.AddNamespace("tei", "http://www.tei-c.org/ns/1.0");

    [System.Xml.XPath.Extensions]::XPathSelectElements($xml, $XPATH_W, $ns) | %{
        $key = $_.Value.ToLower()
        $lemmas = $dict[$key]

        if ($lemmas) {
            $attribute = $_.Attribute($ATTR_LEMMA)
            if ($ProcessTagged -or (-not $attribute)) {
                # Getting distinct list of lemmas.
                $lemmas = ($lemmas | %{ $_.Split(".")[0] } | Sort-Object | Get-Unique)
                $lemmaValue = $null

                # If conversion type is "AllLemmas", we just concatenate all lemmas founded.
                if ($Type -eq "AllLemmas") {
                    $lemmaValue = $lemmas -join "|"
                }
                # If conversion type is "UniqueLemmas" type, we peek lemma value if have only one.
                elseif (($Type -eq "UniqueLemmas") -and ($lemmas.Count -eq 1)) {
                    $lemmaValue = $lemmas
                }

                if ($lemmaValue) {
                    $_.SetAttributeValue($ATTR_LEMMA, $lemmaValue)
                }
            }
        } elseif ($Unknown) {
            $frequency = $unknowns[$key]
            if (-not $frequency) {
                $frequency = 1
            } else {
                $frequency = $frequency + 1
            }
            $unknowns[$key] = $frequency
        }

    }

    # Saving modified XML file
    #$writerSettings = New-Object -TypeName System.Xml.XmlWriterSettings
    #$writerSettings.Encoding = (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false)
    #$writer = [System.Xml.XmlWriter]::Create($Target, $writerSettings)
    #$xml.Save($writer)
    #
    #$reader.Dispose()
    #$writer.Dispose()

    $xml | Set-Content $Target -Encoding UTF8


    # Saving list of unknown lemmas
    if ($Unknown) {
        $unknowns.GetEnumerator() `
            | Sort-Object -Property Value -Descending `
            | %{ "$($_.Key);$($_.Value)" } `
            | Set-Content -Path $Unknown -Encoding UTF8
    }
}

<#
    .SYNOPSIS
    Disambiguator. Cmdlet parses a lemmatized xml source, looks for
    examples where multiple lemma values are possible, and lets users manually choose which single lemma is appropriate in the given context(s).

    .DESCRIPTION
    The lemmatizer functions by:

    - collecting all tokens annotated with multiple possible lemmas (see $XPATH_W variable, (for instance: `//tei:w[contains(@lemma, '|')]`)  as well as their context (sentences, or words before and after)
    - presenting to the user a configurable number of sentences (contexts) in which the given multi-lemma combo appears and the option to chose which of the possible lemmas is appropriate in the given context
    - outputting the fully reconstructed XML file containing only the disambiguated lemma value in the lemma attribute for each of the contexts

    .PARAMETER Source
    Input XML, mandatory.

    .PARAMETER Target
    Output file; optional; by default adds a suffix .disambiguated before the .xml suffix, so that the input file `VSK.P13.sample.xml` will be saved as `VSK.P13-sample.disambiguated.xml`.

    .PARAMETER Context
    With context "Sentence", the disambiguator will declare the context for each multilemma word to be a sentence, i.e. the tei:s node which is the parent of the  given `tei:w[contains(@lemma, '|')]`. Optional parameter. If the parameter is missing, the default is sentence.

    With context "Siblings", the disambiguator will declare the context for each multilemma combo to be a configurable number of siblings to the given `tei:w[contains(@lemma, '|')]` both on the left and right. This will be used for files that don't have explicit tags for sentences.

    .PARAMETER SiblingsNumber
    This parameter is allowed only if we have `-Context Siblings`. The number indicates how many sibling-nodes (both on the left and the right) should be picked up by the script as the context for the given token.

    .PARAMETER ContextsPerWindow
    This parameter indicates the number of contexts that the user will be considering at a time.
    Default vlaue: 5.

    .EXAMPLE
	    Use-Disambiguator `
	        -Source VSK.P13-sample.xml `
	        -Context "Sentence" `
	        -ContextsPerWindow 3
#>
Function Use-Disambiguator {
    Param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Source,

        [Parameter(Mandatory = $false, Position = 1)]
        [string]$Target,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Sentence", "Siblings", IgnoreCase = $true)]
        [string]$Context = "Sentence",

        [Parameter(Mandatory = $false)]
        [int]$SiblingsNumber = 5,

        [Parameter(Mandatory = $false)]
        [int]$ContextsPerWindow = 5
    )

    $ATTR_LEMMA = "lemma"
    $ATTR_ID = [System.Xml.Linq.XName]::Get('id', 'http://www.w3.org/XML/1998/namespace')
    $XPATH_W = "//tei:w[contains(@lemma, '|')]"

    $Source = Resolve-Path $Source

    if (-not (Test-Path $Source)) {
        throw "Source file <$Source> not found."
    }

    # If there is no target file defined, we use source file name with ".disambiguated"
    # suffix (before file extension).
    if (-not $Target) {
        $path = [System.IO.FileInfo](Resolve-Path $Source).Path
        $Target = "$($path.DirectoryName)\$($path.BaseName).disambiguated$($path.Extension)"
    }

    $table = @{}

    # Prepare XML reader ###########################################################################
    $readerSettings = New-Object -TypeName System.Xml.XmlReaderSettings
    $readerSettings.IgnoreWhitespace = $false
    $reader = [System.Xml.XmlReader]::Create($Source, $readerSettings)
    [System.Xml.Linq.XDocument]$xml = [System.Xml.Linq.XDocument]::Load($reader)
    $nt = New-Object -TypeName System.Xml.NameTable
    $ns = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $nt
    $ns.AddNamespace('tei', 'http://www.tei-c.org/ns/1.0')
    $ns.AddNamespace('xml', 'http://www.w3.org/XML/1998/namespace')

    try {
        # For each word (//tei:w) with lemmas (@lemma) we build a hashtable with frequencies calculated.
        [System.Xml.XPath.Extensions]::XPathSelectElements($xml, $XPATH_W, $ns) | %{
            $node = $_

            $lemmas = $node.Attribute($ATTR_LEMMA).Value
            $item = $table[$lemmas]
            if (-not($item)) {
                $item = New-Object PSObject -Property @{
                    Value = $lemmas
                    Count = 0
                    Words = @()
                }

                $table[$lemmas] = $item
            }

            $item.Count++
            $item.Words = $item.Words + $node
        }
    } finally {
        $reader.Dispose()
    }

    # Convert hashtable to the list ordering from the most frequent.
    $table = $table.Values | Sort-Object -Property Count -Descending

    $continue = $true
    $table | %{
        $lemmas = $_
        $words = $lemmas.Words.Length

        # Windowing all lemma occurences by provided context size.
        for ($window = 0; ($window -lt $words) -and ($continue); $window += $ContextsPerWindow) {
            $contexts = 0

            for ($index = $window; ($index -lt $words) -and ($index -lt $window + $ContextsPerWindow); $index++) {
                $word = $lemmas.Words[$index]

                # Pick left siblings
                $left = [System.Xml.XPath.Extensions]::XPathSelectElements($word, 'preceding-sibling::tei:w', $ns) | %{ $_.Value }
                if ($Context -eq 'Siblings') {
                    $left = $left | Select -Last $SiblingsNumber
                }
                if ($left) {
                    $left = [string]::Join(' ', $left)
                } else {
                    $left = ''
                }

                # Pick right siblings
                $right = [System.Xml.XPath.Extensions]::XPathSelectElements($word, 'following-sibling::tei:w', $ns) | %{ $_.Value }
                if ($Context -eq 'Siblings') {
                    $right = $right | Select -First $SiblingsNumber
                }
                if ($right) {
                    $right = [string]::Join(' ', $right)
                } else {
                    $right = ''
                }

                Write-Host ("{0}. {1}" -f ($index - $window + 1), $left) -NoNewline
                Write-Host (" {0} " -f $word.Value) -NoNewline -ForegroundColor $script:WORD_COLOR
                Write-Host $right

                $contexts = $contexts + 1
            }

            Write-Host "`nOptions`n"

            $c = [int][char]'a'
            $items = $lemmas.Value.Split('|')
            $items | %{
                Write-Host ("{0}. " -f [char]$c) -NoNewline
                Write-Host $_ -ForegroundColor $script:WORD_COLOR
                $c = $c + 1
            }

            Write-Host

            do {
                $repeat = $false

                do {
                    Write-Host "Is the same lemma used in all the contexts above? [Y/N/Q(uit)]: " -NoNewline
                } until (($q = ReadInputChar -Valid y, n, q) -ne $null)

                if ($q -eq 'y') {
                    # Each lemmas are numbered from 'a' to 'z' so we calculate $min and $max.
                    $min = [int][char]'a'
                    $max = $min + $items.Length - 1

                    do {
                        Write-Host ("Select a single lemma for the above contexts [{0}-{1}]: " -f [char]$min, [char]$max) -NoNewline
                    } until ($lemma = ReadInputChar -Min ([char]$min) -Max ([char]$max))

                    $selected = $items[[int]$lemma - [int][char]'a']

                    for ($index = $window; ($index -lt $words) -and ($index -lt $window + $ContextsPerWindow); $index++) {
                        $word = $lemmas.Words[$index]
                        $word.SetAttributeValue($ATTR_LEMMA, $selected)
                    }
                } elseif ($q -eq 'n') {
                    $items | %{
                        $lemma = $_
                        Write-Host ("Match lemma `"$($lemma)`" to contexts [{0}-{1}]: " -f 1, $contexts) -NoNewline

                        $selected = Read-Host
                        if ($selected) {
                            $selected = IntArrayFromString($selected)
                            $selected | %{
                                if ($_ -in 1..$contexts) {
                                    $word = $lemmas.Words[$window + $_ - 1]
                                    $word.SetAttributeValue($ATTR_LEMMA, $lemma)
                                }
                            }
                        }
                    }
                } else {
                    Write-Host "Continue disambiguating [y/n]: " -NoNewline
                    $continue = (ReadInputChar -Valid y, n) -eq 'y'

                    if ($continue) {
                        $repeat = $true
                    }
                }
            } until (-not($repeat))

            Write-Host "`n"
        }
    }

    $xml | Set-Content $Target -Encoding UTF8
}
