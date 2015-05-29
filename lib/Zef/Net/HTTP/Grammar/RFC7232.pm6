# Hypertext Transfer Protocol (HTTP/1.1): Conditional Requests

role Zef::Net::HTTP::Grammar::RFC7232 {
    token ETag { <.entity-tag> }

    # token HTTP-date 7231

    token If-Match {
        ||  '*'
        ||  [[<.OWS> <entity-tag>]*] *%% ','
    }

    token If-Modified-Since { <.HTTP-date> }

    token If-None-Match {
        || '*'
        || [[<.OWS> <entity-tag>]*] *%% ','
    }

    token If-Unmodified-Since { <.HTTP-date> }
    token Last-Modified       { <.HTTP-date> }

    # token OWS 7230

    token entity-tag { <.weak>? <.opaque-tag> }

    token etagc { 
        || '!'
        || <[\x[23]..\x[7E]]>
        || <.obs-text>
    }

    # token obs-text 7230

    token opaque-tag { <.DQUOTE> <.etagc>* <.DQUOTE> }
    token weak       { \x[57]\x[2F]                  }
}
