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

```
_ = value(greeting)
_ = lowercase(_)
condition(greeting), .equals, "hi")

```