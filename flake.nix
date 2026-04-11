{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in
    {

      packages.x86_64-linux.sunshine = (
        (pkgs.sunshine.override {
          python3 = (
            pkgs.python3.withPackages (
              py-pkgs: with py-pkgs; [
                setuptools
                jinja2
              ]
            )
          );
        }).overrideAttrs
          (
            oldAttrs:
            let
              ffmpegBinaries = pkgs.stdenv.mkDerivation rec {
                name = "sunshine-ffmpeg-binaries";
                version = "v2026.323.141148";
                src = pkgs.fetchzip {
                  url = "https://github.com/LizardByte/build-deps/releases/download/${version}/Linux-x86_64-ffmpeg.tar.gz";
                  hash = "sha256-jL4Ar5LNBaVrJu1BcAfQFhnSnixS2eL/T2xaIufVsg8=";
                };

                installPhase = ''
                  mkdir -p $out
                  cp -ar . "$out"
                '';
              };
            in
            rec {
              version = "v2026.409.171120";

              src = pkgs.fetchFromGitHub {
                owner = "LizardByte";
                repo = "Sunshine";
                tag = "${version}";
                hash = "sha256-wMm7KgbN3yxfUtJ6b+ScYlDoJS30CZzHHOBhgE/iW6g=";
                fetchSubmodules = true;
              };

              ui = pkgs.buildNpmPackage {
                inherit src version;
                pname = "sunshine-ui";
                npmDepsHash = "sha256-kCScE2JJoZlV05JrHvnXKoWl/TxIN+jDdaDD40qraxQ=";

                # use generated package-lock.json as upstream does not provide one
                postPatch = ''
                  cp ${./sunshine-package-lock.json} ./package-lock.json
                '';

                installPhase = ''
                  runHook preInstall

                  mkdir -p "$out"
                  cp -a . "$out"/

                  runHook postInstall
                '';

              };
              postPatch = # don't look for npm since we build webui separately
              ''
                substituteInPlace cmake/targets/common.cmake \
                  --replace-fail 'find_program(NPM npm REQUIRED)' ""
              ''
              # use system boost instead of FetchContent.
              # FETCH_CONTENT_BOOST_USED prevents Simple-Web-Server from re-finding boost
              + ''
                substituteInPlace cmake/dependencies/Boost_Sunshine.cmake \
                  --replace-fail 'set(BOOST_VERSION "1.89.0")' 'set(BOOST_VERSION "${pkgs.boost.version}")'
                echo 'set(FETCH_CONTENT_BOOST_USED TRUE)' >> cmake/dependencies/Boost_Sunshine.cmake
              ''
              # remove upstream dependency on systemd and udev
              + ''
                substituteInPlace cmake/packaging/linux.cmake \
                  --replace-fail 'find_package(Systemd)' "" \
                  --replace-fail 'find_package(Udev)' ""

                substituteInPlace packaging/linux/dev.lizardbyte.app.Sunshine.desktop \
                  --subst-var-by PROJECT_NAME 'Sunshine' \
                  --subst-var-by PROJECT_DESCRIPTION 'Self-hosted game stream host for Moonlight' \
                  --subst-var-by SUNSHINE_DESKTOP_ICON 'sunshine' \
                  --subst-var-by CMAKE_INSTALL_FULL_DATAROOTDIR "$out/share" \
                  --subst-var-by PROJECT_FQDN 'dev.lizardbyte.app.Sunshine'

                substituteInPlace packaging/linux/app-dev.lizardbyte.app.Sunshine.service.in \
                  --subst-var-by PROJECT_DESCRIPTION 'Self-hosted game stream host for Moonlight' \
                  --replace-fail '/bin/sleep' '${pkgs.lib.getExe' pkgs.coreutils "sleep"}'
              '';

              cmakeFlags = oldAttrs.cmakeFlags ++ [
                (pkgs.lib.cmakeFeature "FFMPEG_PREPARED_BINARIES" "${ffmpegBinaries}")
              ];

              nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [
                pkgs.vulkan-loader
                pkgs.vulkan-headers
                pkgs.shaderc
                pkgs.pipewire
                ffmpegBinaries
              ];

              buildInputs = oldAttrs.buildInputs ++ [
                pkgs.nv-codec-headers-12
              ];
            }
          )
      );

      packages.x86_64-linux.default = self.packages.x86_64-linux.sunshine;

    };
}
