# helper functions to render references in various styles

const tex2unicode_chars = Dict(
    'o' => "\u00F8",  # \o 	ø 	latin small letter O with stroke
    'O' => "\u00D8",  # \O 	Ø 	latin capital letter O with stroke
    'l' => "\u0142",  # \l 	ł 	latin small letter L with stroke
    'L' => "\u0141",  # \L 	Ł 	latin capital letter L with stroke
    'i' => "\u0131",  # \i 	ı 	latin small letter dotless I
)

const tex2unicode_replacements = (
    "---" => "—", # em dash needs to go first
    "--"  => "–",

    # do this before tex2unicode_chars or it wont be recognized
    r"\\\\\"\{\\i\}" => s"\u0069\u308", # \"{\i} 	ï 	Latin Small Letter I with Diaeresis

    # replace quoted single letters before the remaining replacements, and do
    # them all at once, as these patterns rely on word boundaries which can
    # change due to the replacements we perform
    r"\\[oOlLi]\b" => c -> tex2unicode_chars[c[2]],
    r"\\`\{(\S{1})\}" => s"\1\u300", # \`{o} 	ò 	grave accent
    r"\\'\{(\S{1})\}" => s"\1\u301", # \'{o} 	ó 	acute accent
    r"\\\^\{(\S{1})\}" => s"\1\u302", # \^{o} 	ô 	circumflex
    r"\\~\{(\S{1})\}" => s"\1\u303", # \~{o} 	õ 	tilde
    r"\\=\{(\S{1})\}" => s"\1\u304", # \={o} 	ō 	macron accent (a bar over the letter)
    r"\\u\{(\S{1})\}" => s"\1\u306",  # \u{o} 	ŏ 	breve over the letter
    r"\\\.\{(\S{1})\}" => s"\1\u307", # \.{o} 	ȯ 	dot over the letter
    r"\\\\\"\{(\S{1})\}" => s"\1\u308", # \"{o} 	ö 	umlaut, trema or dieresis
    r"\\r\{(\S{1})\}" => s"\1\u30A",  # \r{a} 	å 	ring over the letter (for å there is also the special command \aa)
    r"\\H\{(\S{1})\}" => s"\1\u30B",  # \H{o} 	ő 	long Hungarian umlaut (double acute)
    r"\\v\{(\S{1})\}" => s"\1\u30C",  # \v{s} 	š 	caron/háček ("v") over the letter
    r"\\d\{(\S{1})\}" => s"\1\u323",  # \d{u} 	ụ 	dot under the letter
    r"\\c\{(\S{1})\}" => s"\1\u327",  # \c{c} 	ç 	cedilla
    r"\\k\{(\S{1})\}" => s"\1\u328",  # \k{a} 	ą 	ogonek
    r"\\b\{(\S{1})\}" => s"\1\u331",  # \b{b} 	ḇ 	bar under the letter
    r"\\t\{(\S{1})(\S{1})\}" => s"\1\u0361\2",  # \t{oo} 	o͡o 	"tie" (inverted u) over the two letters
    r"\{\}" => s"",  # empty curly braces should not have any effect
    r"\{([\w-]+)\}" => s"\1",  # {<text>} 	<text> 	bracket stripping after applying all rules

    # Sources : https://www.compart.com/en/unicode/U+0131 enter the unicode character into the search box
)

function tex2unicode(s)
    for replacement in tex2unicode_replacements
        s = replace(s, replacement)
    end
    return Unicode.normalize(s)
end

function linkify(text, link)
    if isempty(text)
        text = link
    end
    if isempty(link)
        return text
    else
        return "<a href='$link'>$text</a>"
    end
end

function _doi_link(entry)
    doi = entry.access.doi
    return isempty(doi) ? "" : "https://doi.org/$doi"
end


function _initial(name)
    initial = ""
    _name = Unicode.normalize(strip(name))
    if length(_name) > 0
        initial = "$(_name[1])."
        for part in split(_name, "-")[2:end]
            initial *= "-$(part[1])."
        end
    end
    return initial
end


# extract two-digit year from an entry.date.year
function two_digit_year(year)
    if (m = match(r"\d{4}", year)) ≢ nothing
        return m.match[3:4]
    else
        @warn "Invalid year: $year"
        return year
    end
end


# The citation label for the :alpha style
function alpha_label(entry)
    year = isempty(entry.date.year) ? "??" : two_digit_year(entry.date.year)
    if length(entry.authors) == 1
        name = Unicode.normalize(entry.authors[1].last; stripmark=true)
        return uppercasefirst(first(name, 3)) * year
    else
        letters = [_alpha_initial(name) for name in first(entry.authors, 4)]
        if length(entry.authors) > 4
            letters = [first(letters, 3)..., "+"]
        end
        if length(letters) == 0
            return "Anon" * year
        else
            return join(letters, "") * year
        end
    end
end


function _is_others(name)
    # Support "and others", or "and contributors" directly in the BibTeX file
    # (often used for citing software projects)
    return (
        (name.last in ["others", "contributors"]) &&
        (name.first == name.middle == name.particle == name.junior == "")
    )
end


function _alpha_initial(name)
    # Initial of the last name, but including the "particle" (e.g., "von")
    # Used for `alpha_label`
    if _is_others(name)
        letter = "+"
    else
        letter = uppercase(Unicode.normalize(name.last; stripmark=true)[1])
        if length(name.particle) > 0
            letter = Unicode.normalize(name.particle; stripmark=true)[1] * letter
        end
    end
    return letter
end


function format_names(
    entry,
    editors=false;
    names=:full,
    and=true,
    et_al=0,
    et_al_text="et al."
)
    # forces the names to be editors' name if the entry are Proceedings
    if !editors && entry.type ∈ ["proceedings"]
        return format_names(entry, true)
    end
    entry_names = editors ? entry.editors : entry.authors

    if names == :full
        parts = map(s -> [s.first, s.middle, s.particle, s.last, s.junior], entry_names)
    elseif names == :last
        parts = map(
            s -> [_initial(s.first), _initial(s.middle), s.particle, s.last, s.junior],
            entry_names
        )
    elseif names == :lastonly
        parts = map(s -> [s.particle, s.last, s.junior], entry_names)
    elseif names == :lastfirst
        parts = String[]
        # See below
    else
        error("Invalid names=$(repr(names)) not in :full, :last, :lastonly")
    end

    if names == :lastfirst
        formatted_names = String[]
        for name in entry_names
            last_parts = [name.particle, name.last, name.junior]
            last = join(filter(!isempty, last_parts), " ")
            first_parts = [_initial(name.first), _initial(name.middle)]
            first = join(filter(!isempty, first_parts), " ")
            push!(formatted_names, "$last, $first")
        end
    else
        formatted_names = map(parts) do s
            return join(filter(!isempty, s), " ")
        end
    end

    needs_et_al = false
    if et_al > 0
        if length(formatted_names) > (et_al + 1)
            formatted_names = formatted_names[1:et_al]
            and = false
            needs_et_al = true
        end
    end

    namesep = ", "
    if names == :lastfirst
        namesep = "; "
    end

    if and
        str = join(formatted_names, namesep, " and ")
    else
        str = join(formatted_names, namesep)
    end
    if needs_et_al
        str *= " $et_al_text"
    end
    return replace(str, r"[\n\r ]+" => " ")
end


function format_published_in(entry; include_date=true)
    str = ""
    if entry.type == "article"
        str *= entry.in.journal
        if !isempty(entry.in.volume)
            str *= " <b>$(entry.in.volume)</b>"
        end
        if !isempty(entry.in.pages)
            str *= ", $(entry.in.pages)"
        end
    elseif entry.type == "book"
        parts = [entry.in.publisher, entry.in.address]
        str *= join(filter!(!isempty, parts), ", ")
    elseif entry.type ∈ ["booklet", "misc"]
        parts = [entry.access.howpublished]
        str *= join(filter!(!isempty, parts), ", ")
    elseif entry.type == "eprint"
        error("Invalid bibtex type 'eprint'")
        # https://github.com/Humans-of-Julia/BibInternal.jl/issues/22
    elseif entry.type == "inbook"
        parts = [
            entry.booktitle,
            isempty(entry.in.chapter) ? entry.in.pages : entry.in.chapter,
            entry.in.publisher,
            entry.in.address,
        ]
        str *= join(filter!(!isempty, parts), ", ")
    elseif entry.type == "incollection"
        parts = [
            "In: $(entry.booktitle)",
            "editors",
            format_names(entry, true),
            entry.in.pages * ". " * entry.in.publisher,
            entry.in.address,
        ]
        str *= join(filter!(!isempty, parts), ", ")
    elseif entry.type == "inproceedings"
        parts = [
            " In: " * entry.booktitle,
            entry.in.series,
            entry.in.pages,
            entry.in.address,
            entry.in.publisher,
        ]
        str *= join(filter!(!isempty, parts), ", ")
    elseif entry.type == "manual"
        parts = [entry.in.organization, entry.in.address]
        str *= join(filter!(!isempty, parts), ", ")
    elseif entry.type == "mastersthesis"
        parts = [
            get(entry.fields, "type", "Master's thesis"),
            entry.in.school,
            entry.in.address,
        ]
        str *= join(filter!(!isempty, parts), ", ")
    elseif entry.type == "phdthesis"
        parts =
            [get(entry.fields, "type", "Phd thesis"), entry.in.school, entry.in.address,]
        str *= join(filter!(!isempty, parts), ", ")
    elseif entry.type == "proceedings"
        parts = [
            (entry.in.volume != "" ? "Volume $(entry.in.volume) of " : "") *
            entry.in.series,
            entry.in.address,
            entry.in.publisher,
        ]
        str *= join(filter!(!isempty, parts), ", ")
    elseif entry.type == "techreport"
        parts = [
            entry.in.number != "" ? "Technical Report $(entry.in.number)" : "",
            entry.in.institution,
            entry.in.address,
        ]
        str *= join(filter!(!isempty, parts), ", ")
    elseif entry.type == "unpublished"
        if isempty(get(entry.fields, "note", ""))
            @warn "unpublished $(entry.id) does not have a 'note'"
        end
    end
    if include_date && !isempty(entry.date.year)
        str *= " ($(entry.date.year))"
    end
    return str
end


function format_note(entry)
    return strip(get(entry.fields, "note", "")) |> tex2unicode
end


function format_eprint(entry)

    eprint = entry.eprint.eprint
    if isempty(eprint)
        return ""
    end
    archive_prefix = entry.eprint.archive_prefix
    primary_class = entry.eprint.primary_class

    # standardize prefix for supported preprint repositories
    if isempty(archive_prefix) || (lowercase(archive_prefix) == "arxiv")
        archive_prefix = "arXiv"
    end
    if lowercase(archive_prefix) == "hal"
        archive_prefix = "HAL"
    end
    if lowercase(archive_prefix) == "biorxiv"
        archive_prefix = "biorXiv"
    end

    text = "$(archive_prefix):$eprint"
    if !isempty(primary_class)
        text *= " [$(primary_class)]"
    end

    # link url for supported preprint repositories
    link = ""
    if archive_prefix == "arXiv"
        link = "https://arxiv.org/abs/$eprint"
    elseif archive_prefix == "HAL"
        link = "https://hal.science/$eprint"
    elseif archive_prefix == "biorXiv"
        link = "https://www.biorxiv.org/content/10.1101/$eprint"
    end

    return linkify(text, link)

end


# Not a safe tag stripper (you can't process HTML with regexes), but we
# generated the input `html` being passed to this function, so we have some
# control over not having pathological HTML here. Also, at worst we end up with
# punctuation that isn't quite perfect.
_strip_tags(html) = replace(html, r"<[^>]*>" => "")

# Intelligently join the parts with appropriate punctuation
function _join_bib_parts(parts)
    html = ""
    if length(parts) == 0
        html = ""
    elseif length(parts) == 1
        html = strip(parts[1])
        if !endswith(_strip_tags(html), r"[.!?]")
            html *= "."
        end
    else
        html = strip(parts[1])
        rest = _join_bib_parts(parts[2:end])
        rest_text = _strip_tags(rest)
        if endswith(_strip_tags(html), r"[,;.!?]") || startswith(rest_text, "(")
            html *= " " * rest
        else
            if uppercase(rest_text[1]) == rest_text[1]
                html *= ". " * rest
            else
                html *= ", " * rest
            end
        end
    end
    return html
end
