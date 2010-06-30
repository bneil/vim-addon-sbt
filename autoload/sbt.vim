exec scriptmanager#DefineAndBind('s:c','g:vim_addon_sbt', '{}')
let s:c['mxmlc_default_args'] = get(s:c,'mxmlc_default_args', ['--strict=true'])
exec scriptmanager#DefineAndBind('s:b','s:c["sbt_features"]', '{}')

if !exists('g:sbt_debug')
  let g:sbt_debug = 0
endif

" author: Marc Weber <marco-oweber@gxm.de>

" usage example:
" ==============
" requires python!
" map <F2> :exec 'cfile '.sbt#Compile(["mxmlc", "-load-config+=build.xml", "-debug=true", "-incremental=true", "-benchmark=false"])<cr>

" implementation details:
" ========================
" python is used to run a sbt process reused.
" This code is copied and modified. source vim-addon-sbt
" Because Vim is not threadsafe ~compile commands are not supported.
" (There are workaround though)
" You can still use vim-addon-actions to make Vim trigger recompilation
" when you write a file


let s:self=expand('<sfile>:h')

" TODO implement shutdown, clean up ?
"      support quoting of arguments
fun! sbt#Compile(sbt_command_list)

  let g:sbt_command_list = a:sbt_command_list

  if !has('python')
    throw "python support required to run sbt process"
  endif

  " using external file which can be tested without Vim.
  exec 'pyfile '.s:self.'/sbt.py'


  silent! unlet g:sbt_result

python << PYTHONEOF
if sbtCompiler.startUpError != "":
  vim.command("let g:sbt_result='%s'"% sbtCompiler.startUpError)
  sbtCompiler.startUpError = ""
else:
  f = sbtCompiler.sbt(vim.eval('g:sbt_command_list'))
  vim.command("let g:sbt_result='%s'"%f)
PYTHONEOF

  " unlet g:sbt_command_list
  return g:sbt_result
endf

let s:ef = 
      \  '%E\ %#[error]\ %f:%l:\ %m,%C\ %#[error]\ %p^,%-C%.%#,%Z'
      \.',%W\ %#[warn]\ %f:%l:\ %m,%C\ %#[warn]\ %p^,%-C%.%#,%Z'
      \.',%-G\[info\]%.%#'

" no arg? just send "" (enter)
fun! sbt#RunCommand(...)
  let cmd = a:0 > 0 ? a:1 : [""]
  exec "set efm=".s:ef
  exec 'cfile '.sbt#Compile(cmd)
endf

fun! sbt#CompileRHS(usePython, args)
  " errorformat taken from http://code.google.com/p/simple-build-tool/wiki/IntegrationSupport
  let ef= s:ef

  let args = a:args

  " let ef = escape(ef, '"\')
  if !a:usePython
    let args =  ["java", "-Dsbt.log.noformat=true", "-jar", SBT_JAR()] + args
  endif
  let args = actions#ConfirmArgs(args,'sbt command')
  if a:usePython
    return 'call sbt#RunCommand('.string(args).')'
  else
    " use RunQF
    return "call bg#RunQF(".string(args).", 'c', ".string(ef).")"
  endif
endfun

" add feature {{{1

" type is either build or plugins
fun! sbt#PathOf(type, create) abort
  let key = a:type.'filepath'
  if !has_key(s:c, key) || !filereadable(s:c[key])
    let g = 'project/'.a:type.'/*.scala'
    let files = split(glob(g),"\n")
    let s:c[key] = tlib#input#List("s","select local name", files)
  endif
  let f = s:c[key] 
  if !filereadable(f)
    if a:create
      let templates = {}
      let templates['build'] = {}
      let templates['plugins'] = {}

      let templates['build']['basename'] = 'SbtProject.scala'
      let templates['build']['content'] =
            \    ['import sbt._'
            \    ,'class SbtProject(info: ProjectInfo) extends DefaultProject(info)'
            \    ,'{'
            \    ,'}']

      let templates['plugins']['basename'] = 'Plugins.scala'
      let templates['plugins']['content'] =
            \    ['import sbt._'
            \    ,'class Plugins(info: ProjectInfo) extends PluginDefinition(info) {'
            \    ,'}']

      let t = templates[a:type]
      let p = 'project/'.a:type
      let f = p.'/'.t['basename']
      call mkdir(p, 'p')
      call writefile(t['content'],f)
    else
      throw "no ".g." file found"
    endif
  endif
  return f
endf

" imports: ['import foo.bar']
fun! sbt#AddImports(imports)
  for i in a:imports
    " TODO escape, break if import exists
    if search(i) | break | endif
    normal G
    if !search('\<import\>','b')
      normal gg
    endif
    put=i
  endfor
endf

" takes keys. See plugin/sbt.vim, s:b
fun! sbt#AddFeature(...) abort
  for key in a:000
    let feature = s:b[key]
    for type in ['plugins','build']
      let key_names = map(['_imports','_with','_code'],string(type).'.v:val')
      let [ki,kw,kc] = key_names
      let [di,dw,dc] = map(key_names,'has_key(feature,v:val)')
      if di || dw || dc
        let f = sbt#PathOf(type, 1)
        
        exec (strlen(bufname(f)) > 0 ? 'b ' : 'sp ').f
        " add imports
        if di | call sbt#AddImports(feature[ki]) | endif

        " add with traits
        if dw 
          normal gg
          if !search('class') || !search('{')
            echoe "no class found. Can't add with"
          else
            if col('.') > 1
              " put { into new line:
              normal "i<cr>"
            endif
            normal k
            " add "with XX" before opening { as new line if it doesn't exist
            " yet
            for w in feature[kw]
              if search(w,'n') | break | endif
              put='    '.w
            endfor
          endif
        endif

        " add extra code
        if dc 
          if !search('class') || !search('{')
            echoe "no class found. Can't add with"
          else
            " jump to closing }
            normal %k
            for l in feature[kc]
              put=repeat(' ',&sw).l
            endfor
          endif
        endif
      endif
    endfor
  endfor
endf

function sbt#AddFeatureCmdCompletion(ArgLead, CmdLine, CursorPos)
  return filter(keys(s:b),'v:val =~ '.string(a:ArgLead))
endf

" }}}
