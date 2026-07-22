{ pkgs ? import <nixpkgs> {} }:

let
  scriptDir = toString ./.;
in
pkgs.mkShell {
  name = "vfs-doc-tools";

  buildInputs = with pkgs; [
    poppler-utils
    imagemagick
    perl
  ];

  shellHook = ''
    export VFS_SCRIPT_DIR="${scriptDir}"

    pdf2img() {
      bash "$VFS_SCRIPT_DIR/pdf2img.sh" "$@"
    }
    export -f pdf2img

    rename-jpgs() {
      perl "$VFS_SCRIPT_DIR/rename_jpgs.pl" "$@"
    }
    export -f rename-jpgs

    echo "vfs-doc-tools shell ready (poppler-utils + imagemagick + perl)."
    echo ""
    echo "Usage:"
    echo "  pdf2img <folder>                    convert PDFs -> size-limited JPGs"
    echo "  rename-jpgs --dry-run <folder>       preview filename sanitization"
    echo "  rename-jpgs <folder>                 apply the renames"
    echo ""
    echo "Example:"
    echo "  pdf2img ~/Desktop/olga && rename-jpgs ~/Desktop/olga"
  '';
}
