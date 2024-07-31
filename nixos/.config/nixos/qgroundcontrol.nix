{
lib, 
stdenv, 
fetchFromGitHub,
  }:

stdenv.mkDerivation {
pname = "QGroundControl";
version = "4.3.0";
src = fetchFromGitHub {
  # url = "https://github.com/mavlink/qgroundcontrol/archive/refs/tags/v4.3.0.tar.gz";
  # sha256 = "YHxToB9SP8HrXtTdxKA/KLoi4kEQiw+8Gws8u583W7M=";
    owner = "mavlink";
    repo = "qgroundcontrol";
  };

}

