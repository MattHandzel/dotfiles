{ pkgs }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.webrtcvad ps.setuptools ]);
in
pkgs.stdenv.mkDerivation {
  name = "stt-record";
  unpackPhase = "true";
  buildInputs = [ pkgs.makeWrapper ];
  
  installPhase = ''
    mkdir -p $out/bin
    cp ${./stt_record.py} $out/bin/stt-record
    chmod +x $out/bin/stt-record
    
    # Replace the shebang with the correct python interpreter
    sed -i '1s|^#!.*|#!${pythonEnv}/bin/python|' $out/bin/stt-record
    
    wrapProgram $out/bin/stt-record \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.ffmpeg pkgs.curl ]}
  '';
}

