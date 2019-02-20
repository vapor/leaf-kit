/// 'base.leaf

```html
<title>#import("title")</title>
#import("body")
```

/// `home.leaf`

```html
#extend("base"):
    #export("title", "Welcome")
    #export("body"): 
        Hello, #(name)! 
    #endexport
#endextend
```

==>

```
raw("<title>")
tagIndicator
tag("import")
parametersStart
string("title")
parametersEnd
raw("<\title>\n")
tagIndicator
tag("import")
parametersStart
string("body")
parametersEnd
```

```
tagIndicator
tag("extend")
parametersStart
string("base")
parametersEnd
bodyIndicator
tagIndicator
tag("export")
parametersStart
string("title")
parametersDelimitter
string("Welcome")
parametersEnd
tagIndicator
tag("export")
parametersStart
string("body")
parametersEnd
bodyIndicator
raw("\nHello, ")
tagIndicator
tag("")
parametersStart
variable("name")
parametersEnd
raw("!\n")
tagIndicator
tag("endexport")
tag("endextend")
```

==>

```
raw("<title>Welcome</title>\nHello, ")
value(of: name)
raw("!")
```

//////////////////////////////////////////////////////

```
#if(lowercase(greeting) == "hi"):
hello
#else:
goodbye
#endif
```

# FOOO

(lldb) po print(input)
```
#extend("base"):
    #export("title", "Welcome")
    #export("body"):
        Hello, #(name)!
    #endexport
#endextend
```

(lldb) po print(lexed)
```
tagIndicator
tag(name: "extend")
parametersStart
param(stringLiteral("base"))
parametersEnd
tagBodyIndicator
raw("\n    ")
tagIndicator
tag(name: "export")
parametersStart
param(stringLiteral("title"))
parameterDelimiter
param(stringLiteral("Welcome"))
parametersEnd
raw("\n    ")
tagIndicator
tag(name: "export")
parametersStart
param(stringLiteral("body"))
parametersEnd
tagBodyIndicator
raw("\n        Hello, ")
tagIndicator
tag(name: "")
parametersStart
param(variable(name))
parametersEnd
raw("!\n    ")
tagIndicator
tag(name: "endexport")
raw("\n")
tagIndicator
tag(name: "endextend")
```

(lldb) po print(output)
```
extend(parameter(stringLiteral("base")))
raw("\n    ")
export(hasBody: false: parameter(stringLiteral("title")), parameter(stringLiteral("Welcome")))
raw("\n    ")
export(hasBody: true: parameter(stringLiteral("body")))
raw("\n        Hello, ")
variable(parameter(variable(name)))
raw("!\n    ")
tagTerminator(export)
raw("\n")
tagTerminator(extend)
```
