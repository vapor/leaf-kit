Leaf4 is a dynamic language templating engine for (and inspired by) Swift with a unique hybrid design to allow significant extensibility, customization, performance, and optimizations for a broad range of applications. Leaf templates function primarily as the **View** component of *Model-View-Controller* architectures.

As the successor to Leaf3, it greatly expands the language's capabilities and introduces significant changes that are oriented towards: simplfying integration of Leaf into applications; broader use beyond web-templating; robust handling of compiling templates; and improved, more powerful, and safer extensibility of templates at runtime.

[LeafKit](https://github.com/vapor/leaf-kit) is the core architecture of Leaf4; for the bindings of LeafKit to [Vapor](https://github.com/vapor/vapor) and Vapor-specific configuration, see [Leaf](https://github.com/vapor/leaf) - hereafter, **Leaf** is understood to refer to LeafKit/Leaf4.

## Architectural Summary

------

Leaf serializes an output buffer of data by interpolating a **context** (of data values) into a compiled **template**. 

At the simplest level, a Leaf template consists of **Leaf** tags (denoted by a **tag indicator** - by default, `#`) interleaved in a stream of **Raw** content. Leaf tags may consist of data, expressions, named functions, or may be scope-creating blocks themselves; when rendering a Leaf template, any content that is *not* prefaced by Leaf's tag indicator is considered raw input and is passed directly to the output stream.

Leaf maintains a database of all named entities (**functions**, **methods**, **blocks**, etc) a particular usage has configured to guarantee that a running application will present a consistent view of the application's use of the language across all render calls to Leaf during its running lifecycle.

Leaf templates themselves may **declare** variables, may **inline** other templates or raw files to construct hierarchical views, and may **define** anonymous blocks which can be **evaluated** at later times based on the state of the serializing process.

LeafKit guarantees that a running application using it will present a consistent view of the configured language across all render calls to Leaf.

## Leaf Data Types

------

A configured Swift application using Leaf typically passes model data as a **context** to Leaf, and thus vends its data to a template as variables. Leaf itself is *not* a typed language and requires no type declarations in templates, but is nonetheless fully-typed internally as data passed to it is held internally in native Swift types.

All valued types (with the exception of `Data`) can be literally typed in Leaf templates in addition to being passed in as context data.

Atomic types Leaf have one-to-one equivalencies with native Swift types:

* Bool (Swift `Bool`)
* Int (Swift `Int`) 
* Double (Swift `Double`)
* String (Swift `String`)
* Data (Swift `Data`)

Collection types:

* Array (A zero-indexed array whose elements may be of any Leaf data type)
* Dictionary (A string-keyed dictionary whose elements may be of any Leaf data type)

Additional types:

* Leaf data values can also present *optional* states (equivalent to Swift `Optional`) for any atomic or collection type, I.E: `Bool?, Int?, Double?, String?, Data?, Array?, Dictionary?`
* Non-evaluable parameters have a `Void` value, which will not be appended to the output buffer (E.G: a Leaf comment, or a variable declaration).
* A special case of `trueNil` (represented as `Void?`) is never directly passed by any function and indicates a soft erroring state that stops the evaluation of a Leaf parameter, but continues the serialization of a template.
* Error states may be thrown programmatically by functions or the template to stop serialization - depending on configuration of Leaf, these can be configured to rather convert to `trueNil`. As an example, the default configuration of LeafKit considers a variable name used in the template which does not exist in its context values to be an error.

#### Data Type Coercion and Casting

Leaf data types are type-checked when templates are compiled based to the greatest extent possible, and explicitly checked at serialize time when variables and expressions are resolved, so no explicit type declarations are ever necessary. Functions themselves specify which types their parameters accept (anything except `Void`).

Effectively, all Leaf tags are implicitly optionally-chained.

In the case of a function which takes a `String` parameter - should the provided parameter fail to be a concrete `String` or a type which can be implicitly coerced to a `String` at serializing time - the function itself will *not* be evaluated, and the resulting expression, function, or block will not be appended to the output stream.

## Leaf Identifiers and Keywords

------

Leaf is type-sensitive and has structural requirements for identifiers for variables and function names:

* Must start with an upper- or lower-case Roman character (`a-z, A-Z`) or an underscore `_`
* Remaining body of identifier can also contain decimal numbers (`0-9`)

The following keywords are protected in Leaf and may not be used as an identifier:

`leaf, self, nil, var, let, true, false, yes, no, in, _`

## Leaf Parameters

------

All Leaf tags take zero or more parameters, which can consist of:

* Literal values (equating to any of the possible Leaf data types) 
* Evaluable keywords (`self, true, false, yes, no, nil`)
* Variables (`aVariable`)
* Dot-notation pathed variables (`aVariable.subValue`)
* Function and method calls (`function()`, `value.method()`)
* Subscripting (`arrayValue[integerIndex]`, `dictionaryValue["stringIndex"]`)
* Complex expressions (`!x || y && z`) 
* Variable declarations ()`let x`, `var x = 100`)
* Comments (`# A Comment #`)

Each type of parameter will be detailed later in this guide.

## Basic Syntaxes

------

### Anonymous Tags

The most basic tag is an anonymous expression, which may have zero or one evaluable parameters. If there is an evaluable parameter, it is appended to the output stream:

* `#()` has no parameter and has no effect on the output stream.

* `#("Hello World")` writes the string "Hello World" to the output stream.

* `#(aVariable)` will attempt to evaluate a variable named `aVariable`, and if it exists, write its value to the output stream.

### Functions

Leaf supports named, overloaded **function**s with rich, labeled parameter formatting, type-checking, and default values, extremely similar to Swift function calls:

```leaf
#functionOne()
#functionTwo(unlabeledParameter) 
#functionThree(labeled: parameter)
```

If a function's call signature specifies that a parameter has a default value, it can be elided in use. For example, the core Leaf function `#Date()` for ISO8601 date string representations of a given timestamp and a timezone identifier has default values so all of the below call the same function with identical results:

```Leaf
#Date()
#Date("now")
#Date("now", timeZone: "UTC")
```

Function signatures also guarantee unambiguous overloading of function names. For example, three varieties of `#Date()` exist in the core Leaf library (shown in pseudo-code to demonstrate default values):

```swift
// ISO8601 formatted with timezone offset
#Date(timestamp = "now", timeZone: identifier = "UTC")

// Fixed format with timezone offset
#Date(timestamp: timestamp, fixedFormat: format, timeZone: identifier = "UTC")

// Localized format with timezone offset and locale 
#Date(timestamp: timestamp, localizedFormat: format, timeZone: identifier = "UTC", locale: identifier = "en_US_POSIX")`
```

> *NOTE*: Core functions in Leaf with defaulted values typically are configurable system-wide prior to LeafKit running - while the defaults shown here are `UTC` and `en_US_POSIX`, a particular usage of LeafKit is free to change those default values; templates will automatically use the configured version.

### Methods

Leaf supports two forms of **methods**, which are functions that can be called via dot-notation on a Leaf parameter:

* **Non-mutating** methods may be used on any data value in Leaf: 

  ```leaf
  #(var anArray = [])
  #(anArray.count())
  ```

* **Mutating** methods can alter the parameter they operate on and thus can only be used on *non-constant* variables which were declared in the template, not on variables in the **context** passed to the template.

  ```leaf
  #(var array = [])
  #(anArray.append("anElement"))
  ```

### Blocks

A **block** is any structure in Leaf which introduces a possibly-state altering change to the template's compiled behavior - the opening of a block is written identically to a **function** but is followed by the **block indicator**, a colon `:` that states that anything until the block is closed (via #end*nameofblock*) belongs to the block's scope.

```
#for(item in array):
    #(item)
#endfor
```

Just as a variable declared in a typical programming language exists only in the scope where it is declared, variables declared in a block's body, or set by the block itself (as in a `for` loop) are available only until the block is closed.

Certain types of blocks may also be **chained**, in which case each chained block has its own scope and the first to evaluate will cause the additional chained blocks to be ignored.

```
#if(conditionOne):
    Do something
#elseif(conditionTwo):
    Do something else
#else:
    Do a default thing
#endif
```

### Extending LeafKit's Entities

While Leaf templates cannot themselves declare functions, the language can be heavily extended with custom `LeafFunction/Method/Block`s when configuring LeafKit's integration in a Swift application. All but 4 core entities in Leaf4 are built using the publically-available interfaces for extending the language - control flow, variable scoping, and all manner of features can be safely integrated using Swift in a way that is designed to be safely extensible and still extremely performant.

## Leaf Contexts and Variables

------

As previously mentioned, Leaf templates are serialized by interpolating a provided **context** into the compiled template. This context object provides the database of variable values for a particular render call to the template, and as such, variables which exist in the context can be referred to *implicitly*.

> *NOTE*: By default, LeafKit is configured to consider a variable that is not declared anywhere (either in the template itself or in the context passed to it) as a hard error that halts serializing the template. This behavior is configurable globally via `LeafRenderer.Context.missingVariableThrows` or on a per-render basis with render-time options. 

In the example below, the variable `x` is never declared in the template; its value will be implicitly found in the passed context (or will fail if the context does not define it.)

```
#(x)
```

A **context** may actually contain multiple **scopes** of variables; there will always be (at a minimum) the default scope where all implicit variables exist (the Leaf keyword **self**), and which a model context passed implicitly exists in.

```
#(self.x)
```

 If a template declares a variable itself, the original context scope continues to be available at its fully scoped variable identifer:

```
#(x)         <- Equivalent to implicitly accessing "self.x"
#(self.x)    <- Explicit reference to the context's value for x
#(var x = 0) <- Set the declared template value for x to 0
#(x)         <- Now refers to the explicitly declared value of x
#(self.x)    <- Still refers to the original context value for x
```

A Leaf context scope is itself a complete Leaf data value itself - a dictionary of Leaf data can thus be used as a variable in its own right:

```
#(self) <- The `self` implicit context.
```

Advanced configurations of LeafKit may introduce additional named scopes. For example, an advanced application configuration might publish a scope named `auth` which contains information about secured access. They are *never* used as implicit sources of variable values; such additional context scopes must always be accessed via their fully scoped variable identifier - the scope identifier `$` followed by the scope name. 

```
#($auth.user) <- Authenticated user's name
```

#### Declaring Variables

Variables can be explicitly declared inside templates for a variety of uses - either as mutable or constant values, and can be declared without an initial value (value must be set prior to use):

```
#(let w)      <- w is an unset constant value
#(var x)      <- x is an unset mutable value
#(let y = 10) <- y is a constant value of 10
#(var z = x)  <- z is a mutable value currently set to 10
```

#### Scoped Variables

When serializing, Leaf maintains an internal stack; variables can be redefined at any new scoping block. In the example below, the variable `x` is a constant holding the value "X". `x` can be redeclared as a variable within the body of the `if` block and have a value assigned to it. Without the redeclaration of `x` in the scope, the template would fail to compile as `#(x = "Not X")` cannot assign a value to a constant identifier.

```
#(let x = "X")
#if(x == "X"):
        #(var x)
        #(x = "Not X")
#endif
```

## Leaf Operators

------

Leaf supports a typical range of operators on values that themselves produce values:

* Logical Operators which return a Boolean state: 

  ```
  ! rhs      : Unary Not
  lhs == rhs : Equality
  lhs != rhs : Inquality
  lhs > rhs  : Greater Than
  lhs >= rhs : Greater Than or Equal
  lhs < rhs  : Lesser Than
  lhs <= rhs : Lesser Than or Equal
  lhs && rhs : Logical And
  lhs || rhs : Logical Or
  lhs ^^ rhs : Logical Exclusive Or
  ```

* Mathematical operators (require matching or implicit conversion of left- and right-hand sides):

  ```
  lhs + rhs : Addition
  lhs - rhs : Subtraction
  lhs / rhs : Division
  lhs * rhs : Multiplication
  lhs % rhs : Modulus
  ```

* Subscripting on collections:

  ```
  lhs[index] : Array subscripting where index is an Integer
  lhs[key]   : Dictionary subscripting where key is a String
  ```

* Conditional ternary evaluation:

  ```
  condition ? lhs : rhs
  ```

* Nil coalescing:

  ```
  possibleNil ?? defaultValue
  ```

Leaf's parser is capable of wrapping complex expressions without parentheses for grouping operations but use is still advisable for clarity.

```
#(10 + variable ?? 5) <- equivalent to `10 + (variable ?? 5)`
#(!x ^^ !z)                     <- equivalent to `(!x) ^^ (!z)`
```

All operations, with the exception of the assignment operators below, may be used anywhere inside Leaf tags.

* Assignment and compound assignment (on mutable operands only):

  ```
  lhs = rhs  : Assignment
  lhs += rhs : Compound Addition
  lhs -= rhs : Compound Subtraction
  lhs /= rhs : Compound Division
  lhs *= rhs : Compound Multiplication
  lhs %= rhs : Compound Modulus
  ```

 Assignment operators do *not* produce the result of their assignment as a return value and must be used as the only expression in an anonymous tag or in the declaration of a variable:

```
#(var x = 0) <- declares `x` with the value 0
#(x += 10)   <- adds 10 to the value of x
#(x)                 <- outputs the value of x to the output stream
```

## Leaf Comments

------

Comments may be made anywhere inside a Leaf tag by using the **tag indicator** (which is never used inside tag parameters) as delimiters for the comment:

```
#(# An anonymous tag that produces no output is an entire comment #)

#(#
        And can span as many lines as desired
#)

#(aVariable # ... and can also be used inside tags that produce values #)
```

## Metablocks

------

Four core entities enable hierarchical template usage, anonymous evaluable blocks, and buffer control.

### Inlining Additional Files - #inline

`inline` allows a template to be assembled from multiple other files, either by introducing more parseable Leaf template, or raw streamed content. `as` dictates how inlining of the file should be handled; the possible options currently are `leaf` (default) and `raw`.

If `raw` the entire file's contents will be treated as a raw stream that bypasses processing and is fed directly to the output stream when `inline` is executed.

If `leaf`, the file will be read as a Leaf template itself, and will have access to the entire state of the template it is inlined to, both original context values and the current state of the variable stack at the scope where `inline` is executed.

```
#inline(String, as: identifier = leaf)
```

> *NOTE*: the file parameter to inline curently *must be a literal value*, not a variable.

### Deferred Value/Block Evaluation - `define` and `evaluate`

While Leaf has no direct concept of declaring functions directly within a template, there is one exception: deferred evaluation of defined blocks. For advanced Swift programmers, this is similar in concept to an escaping closure of type `()-> Any` or `() -> Void`

Identifiers for deferred execution exist in a separate scope from variables - a variable `x` and a deferred definition of `x` do *not* conflict and will not cause ambiguous results.

#### define

`define` takes two forms; as a function, and as a block. In both cases, the first parameter is a valid Leaf identifier which will later be used to evaluate the definition, and either a parameter or block body is provided *but not evaluated*.

```
#define(identifier, value)

#define(identifier):
 *Body*
#enddefine
```

These **definitions** can later be called at any point using a corresponding `evaluate` call, which will evaluate the parameter or body with the serializing state *at the point of the evaluation call*, **NOT** the state at the point when the definitions were created.

Definitions are overriden by subsequent definitions in the same way that assigning a new value to a variable overrides the previous value:

```
#define(identifier, aVariable)
#define(identifier, aVariable + 10)
```

#### evaluate

`evaluate` can be called in two ways, either solely with an identifier, or with an identifier with a coalesced argument to excute should the provided identifier not exist in context.

```
#evaluate(identifier)
#evaluate(identifer ?? defaultValue)
```

Note that if the definition made prior for the identifier was the function-form with a value rather than a block body, evaluating can occur nested inside parameters; see the following example:

```
#(var array = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
#(var x)

`indexed` can be used by evaluate in parameters:
#define(indexed, "Result: " + array[array.count() - 1])

#(evaluate(indexed) == "Result: 9") <- true
#(array.append(0))
#(evaluate(indexed) == "Result: 0") <- true

`indexed` can only be used by evaluate as a top level function.
#define(indexed):                                                     
Result: #(array[array.count() - 1]) 
#enddefine

#evaluate(indexed) <- writes "Result: 0" to the output stream
```

> *NOTE*: Convenience shorthands for the functions are available - `def` and `eval` are synonyms for the two metablocks.

### RawBlocks

> *NOTE*: Alteration of the output stream's raw state using metablocks is not yet enabled publicly. TBA.

## Core Entities

------

The core entities of Leaf are described here in pseudocode specifying the value types their parameters expect and any default that may exist.

### Control Flow

------

Leaf core control flow structures supports three basic types: conditional `if` chains, `for` loops, and `while` loops.

#### if

`if` control flow blocks consist of a chain of a single `if` and optional `elseif`s, and an optional terminating `else` block. The first block whose condition evaluates to true is excuted, and the remaining blocks are ignored. If an `else` block is present and no preceeding block executes, it will always default (but is not required).

```
#if(Boolean):       <- Exactly one `if` block opens the conditional chain
#elseif(Boolean):   <- Zero or more `elseif` blocks may chain on
#else:                            <- Exactly zero or one `else` block terminates the chain
#endif                          <- Closed by `endif`
```

#### while

`while` control flow blocks execute their body repeatedly while the parameter evaluates to true.

```
#while(Boolean):
#endwhile
```

#### for

`for` control flow blocks have several variations that excute a fixed number of loops over a provided value, and also set variables in the scope of their body.

In the pseudo-code below, `collection` may be any value of type `Int`, `String`, `Array`, or `Dictionary`. All forms loop over the count of the collection provided - Int arguments are inferred to be an array of [0..<value], String arguments are converted to an Array of their contents, and Array & Dictionary types represent themselves.

In all cases, the `for` loop publishes the variables `isFirst` and `isLast` to indicate if the execution of the loop's body is at the start and/or the end of the loop. The variations below differ in what additional variables they publish to the loop's body scope:

```
#for(_ in collection)
Discard value - publishes no additional variables.

#for(identifier in collection)
Provides the value of the collection's item at that loop position as `identifier`

#for(identifier in collection)
Provides the index/key of the collection item at that loop position if `identifier` is explicitly `index` or `key`

#for((identifier, identifier) in collection)
Provides both the index/key and value of the collection's item at that loop position

```

### Type Casts and Identity

------

Type casts are unnecessary for Leaf to function, but are occasionally useful where an entity name is overloaded for different types, or to clarify call sites. In all cases, the function takes a parameter of the type specified and returns the parameter with no changes.

```
#Bool(Boolean) -> Boolean
#Int(Integer) -> Integer
#Double(Double) -> Double
#String(String) -> String
#Array(Array) -> Array
#Dictionary(Dictionary) -> Dictionary
#Data(Data) -> Data
```

Type identity functions return the underlaying type representation of concrete types as a string - such as `Int`, `Int?`, `String`, `String?`, etc.

```
#type(of: Any?) -> String
#(any.type()) -> String
```

### Erroring

------

Errors to terminate serializing can be created via the following functions:

```
Error(String = "Unknown serialize error")
throw(reason: String = "Unknown serialize error")
```

> *NOTE*: Global behaviors can cause errored value states to be reduced to a `Void?` state that will *not* terminate serializing. While no current behavior disambiguates between `Error` and `throw`, `throw` is intended as a *harder* error which may, in the future, *always* halt serializing and not be reducalbe to a soft failing state.

### Int Functions and Methods

------

**Non-mutating**

`min` and `max` provide computational results on the two parameters

`formatBytes` provides a very basic that presents an Integer value in bytes as B/KB/MB/GB as appropiate, to provided number of decimal places.

```
min(Int, Int) -> Int
max(Int, Int) -> Int

Int.formatBytes(places: Int = 2) -> String
formatBytes(Int, places: Int = 2) -> String
```

### Double Functions and Methods

------

**Non-mutating**

`min` and `max` provide computational results on the two parameters

`rounded` rounds the operand to the number of places, positive to the right of the decimal point, negative to the left.

`formatBytes` provides a very basic that presents an Double value of seconds as s/ms/µs as appropiate, to provided number of decimal places.

```
min(Double, Double) -> Double
max(Double, Double) -> Double

Double.rounded(places: Int) -> Double

Double.formatSeconds(places: Int = 2) -> String
formatSeconds(Double, places: Int = 2) -> String
```

### String Functions and Methods

------

**Non-mutating**

`uppercased`, `lowercased`, `reversed`, `replace` and `escapeHTML` always produce a resultant String with the applied transformation.

`randomElement` returns a random element from the string or nil if empty.

`hasPrefix`, `hasSuffix`, `contains` and `isEmpty` return a Boolean value for the truth of the function. 

`count` returns the number of characters in the string.

`escapeHTML` provides extremely basic subsitution of `<, >, &, ", '` in the input String (*Note* does not validate that ampersands are not already escaped)

```
String.uppercased() -> String
String.lowercased() -> String
String.reversed() -> String
String.replace(occurencesOf: String, with: String) -> String

String.randomElement() -> String?

String.hasPrefix(String) -> Bool
String.hasSuffix(String) -> Bool
String.contains(String) -> Bool
String.isEmpty() -> Bool

String.count() -> Int

String.escapeHTML() -> String
escapeHTML(String) -> String
```

**Mutating**

`append` adds the parameter to the end of the operand String

`popLast` removes and returns the last character of the operand String if one exists

```
String.append(String)
String.popLast() -> String?
```

### Array Functions and Methods

------

**Non-mutating**

`count` returns the number of elements in the Array.

`indices` returns an Array of the subscripting indices of the operand.

`contains` and `isEmpty` return a Boolean value for the truth of the function.

```
Array.count() -> Int
Array.indices() -> Array

Array.isEmpty() -> Bool
Array.contains(Any) -> Bool
```

**Mutating**

`append` adds the parameter to the end of the operand `Array`

`popLast` removes and returns the last item of the operand `Array` if one exists

```
Array.append(Any)
Array.popLast() -> Any?
```

### Dictionary Functions and Methods

------

**Non-mutating**

`count` returns the number of elements in the Dictionary.

`keys` and `values` return Arrays of the corresponding aspects of the Dictionary.

`indices` returns an Array of the subscripting indices of the operand.

`contains` and `isEmpty` return a Boolean value for the truth of the function.

```
Dictionary.count() -> Int

Dictionary.keys() -> Array
Dictionary.values() -> Array

Dictionary.isEmpty() -> Bool
Dictionary.contains(Any) -> Bool
```

