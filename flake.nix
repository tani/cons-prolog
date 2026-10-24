{
  description = "Cons Prolog: multi-implementation Common Lisp library and tests";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ flake-parts.flakeModules.easyOverlay ];
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      perSystem = { config, pkgs, lib, system, ... }:
        let
          pname = "cons-prolog";
          version = "0.10.0";
          src = lib.cleanSource ./.;
          implementations = {
            sbcl = { program = "sbcl"; args = "--noinform --disable-debugger"; eval = "--eval"; };
            ecl = { program = "ecl"; args = "-norc"; eval = "--eval"; };
            abcl = { program = "abcl"; args = "--noinform --noinit"; eval = "--eval"; };
            ccl = { program = "ccl"; args = "--quiet --no-init"; eval = "--eval"; };
            mkcl = { program = "mkcl"; args = "-norc"; eval = "-eval"; };
            clisp = { program = "clisp"; args = "-q -norc"; eval = "-x"; };
            cmucl_binary = { program = "lisp"; args = "-quiet -noinit"; eval = "-eval"; };
            clasp-common-lisp = { program = "clasp"; args = "--noinform --norc"; eval = "--eval"; };
          };
          available = lib.filterAttrs (impl: _: let
            candidate = builtins.tryEval pkgs.${impl};
          in candidate.success
            && lib.meta.availableOn pkgs.stdenv.hostPlatform candidate.value
            && !(candidate.value.meta.broken or false)
          ) implementations;
          recipe = lib.mapAttrs (impl: options: let
            lisp = pkgs.${impl};
            library = lisp.buildASDFSystem {
              inherit pname version src;
              systems = [ "cons-prolog" "cons-prolog/tests" ];
              lispLibs = [];
              nativeLibs = [];
              preBuild = ''export XDG_CACHE_HOME="$TMPDIR/asdf-cache"'';
            };
            runtime = lisp.withPackages (_: [ library ]);
            test = pkgs.writeShellScriptBin "cons-prolog-test" ''
              exec ${runtime}/bin/${options.program} ${options.args} \
                ${options.eval} '(require "asdf")' \
                ${options.eval} '(handler-case (progn (asdf:test-system "cons-prolog") (uiop:quit 0)) (error (condition) (format *error-output* "~&~A~%" condition) (uiop:quit 1)))'
            '';
            # Cons Prolog is a library: main-* starts a REPL with its API loaded.
            main = pkgs.writeShellScriptBin "cons-prolog" ''
              exec ${runtime}/bin/${options.program} ${options.args} \
                ${options.eval} '(require "asdf")' \
                ${options.eval} '(progn (asdf:load-system "cons-prolog") (use-package :prolog))' ${lib.optionalString (impl == "clisp") "-repl"} "$@"
            '';
            check = pkgs.runCommand "cons-prolog-test-${impl}" {} ''
              mkdir -p "$TMPDIR/asdf-cache"
              export XDG_CACHE_HOME="$TMPDIR/asdf-cache"
              ${test}/bin/cons-prolog-test
              touch "$out"
            '';
          in { inherit library runtime test main check; }) available;
          attrsFor = prefix: field: lib.mapAttrs' (impl: value:
            lib.nameValuePair "${prefix}-${impl}" value.${field}) recipe;
          appsFor = prefix: field: bin: lib.mapAttrs' (impl: value:
            lib.nameValuePair "${prefix}-${impl}" {
              type = "app";
              program = "${value.${field}}/bin/${bin}";
            }) recipe;
        in {
          packages = attrsFor "lib" "library" // attrsFor "main" "main"
            // attrsFor "test" "test"
            // lib.optionalAttrs (recipe ? sbcl) { default = recipe.sbcl.library; };
          apps = appsFor "main" "main" "cons-prolog" // appsFor "test" "test" "cons-prolog-test";
          checks = attrsFor "test" "check";
          devShells = {
            default = pkgs.mkShell {
              packages = lib.mapAttrsToList (impl: _: pkgs.${impl}) available;
              shellHook = ''export CL_SOURCE_REGISTRY="$PWD//"'';
            };
          } // lib.mapAttrs (impl: _: pkgs.mkShell {
            packages = [ pkgs.${impl} ];
            shellHook = ''export CL_SOURCE_REGISTRY="$PWD//"'';
          }) available;
          overlayAttrs = lib.mapAttrs (impl: _: pkgs.${impl}.withOverrides
            (_: _: { "cons-prolog" = config.packages."lib-${impl}"; })) available
            // lib.mapAttrs' (impl: _: lib.nameValuePair "cons-prolog-${impl}"
              config.packages."main-${impl}") available;
        };
    };
}
