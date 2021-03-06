{ obj-to-lists, zip, concat-map } = require \prelude-ls
es-generate = (require \escodegen).generate _

looks-like-number = (atom-text) ->
  atom-text.match /^\d+(\.\d+)?$/

class string
  (@content-text) ~>

  text : ->
    return @content-text if not it?
    @content-text := it

  as-sm : ->
    type : \Literal
    value : @content-text
    raw : "\"#{@content-text}\""

  compile : ->
    type : \Literal
    value : @content-text
    raw : "\"#{@content-text}\""

class atom
  (@content-text) ~>

  text : ->
    return @content-text if not it?
    @content-text := it

  as-sm : ->
    if @content-text |> looks-like-number
      type  : \Literal
      value : Number @content-text
      raw   : @content-text
    else
      type : \CallExpression
      callee :
        type : \Identifier
        name : \atom
      arguments : [ { type : \Literal, value : @content-text, raw : "\"#{@content-text}\"" } ]

  compile : ->
    if @content-text |> looks-like-number
      type  : \Literal
      value : Number @content-text
      raw   : @content-text
    else
      type : \Identifier
      name : @content-text

class list
  (@content=[]) ~>

  contents : ->
    return @content if not it?
    @content := it

  as-sm : ->
    type : \CallExpression
    callee :
      type : \Identifier
      name : \list
    arguments : [
        type : \ArrayExpression elements : @content.map (.as-sm!)
    ]

  compile : (parent-macro-table, import-target-macro-table) ->

    # The import-target-macro-table argument is for the situation when a macro
    # returns another macro.  In such a case, the returned macro should be
    # added to the table that the macro that created it was in, not to the
    # table representing the scope of the the outer macro's contents.

    # If that's confusing, take a few deep breaths and read it again.  Welcome
    # to the blissful land of Lisp, where everything is recursive somehow.

    macro-table = contents : {}, parent : parent-macro-table

    # Recursively search a macro table and its parents for a macro with a given
    # name.  Returns `null` if unsuccessful; a macro representing the function
    # if successful.
    find-macro = (macro-table, name) ->
      switch macro-table.contents[name]
      | null => null                          # deliberately masks parent; fail
      | undefined =>                          # not defined at this level
        if macro-table.parent
          find-macro macro-table.parent, name # ask parent
        else return null                      # no parent to ask; fail
      | otherwise => that                     # defined at this level; succeed

    return type : \EmptyStatement if @content.length is 0

    [ head, ...rest ] = @content

    return null unless head

    if head instanceof atom
    and find-macro macro-table, head.text!

      env = do
        compile = -> # compile to SpiderMonkey AST
          if it.compile?
            it.compile macro-table
          else it
        compile-many = -> it |> concat-map compile |> (.filter (isnt null))
        compile-to-js = -> es-generate it

        {
          compile
          compile-many
          compile-to-js
          macro-table
          import-target-macro-table
        }

      that.apply null, ([ env ] ++ rest)

    else
      # TODO compile-time check if callee has sensible type
      type : \CallExpression
      callee : head.compile macro-table
      arguments : rest.map (.compile macro-table)

module.exports = { atom, string, list }
