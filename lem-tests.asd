(defsystem "lem-tests"
  :depends-on ("lem-base"
               "lem"
               "lem-lsp-utils"
               "lem-lsp-server"
               "lem-fake-interface"
               "lem-lisp-syntax"
               "lem-lisp-mode"
               "cl-ansi-text"
               "trivial-package-local-nicknames"
               "testif")
  :pathname "tests"
  :components ((:file "utilities")
               (:module "common"
                :components ((:file "ring")
                             (:file "killring")))
               (:module "lsp-utils"
                :components ((:file "json")
                             (:file "json-lsp-utils")))
               (:module "lsp-server"
                :components ((:file "test-server")
                             (:file "initialize")
                             (:file "initialized")
                             (:file "text-document-did-open")))
               (:module "lisp-syntax"
                :components ((:file "indent-test")
                             (:file "defstruct-to-defclass")))
               (:module "lisp-mode"
                :components ((:file "package-inferred-system")))
               (:file "string-width-utils")
               (:file "syntax-test")
               (:file "buffer-list-test")
               (:file "popup-window")
               (:file "prompt")
               (:file "isearch")
               (:file "cursors")
               (:file "self-insert-command")
               (:file "interp"))
  :perform (test-op (o c)
                    (symbol-call :testif :run-tests)))
