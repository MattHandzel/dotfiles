{
  lib,
  python3Packages,
  fetchPypi,
}: let
  bubop = python3Packages.buildPythonPackage rec {
    pname = "bubop";
    version = "0.1.12";
    format = "pyproject";
    src = fetchPypi {
      inherit pname version;
      sha256 = "12sh6gij5994896jyz00fd79rasrydhwxczzsqbbivjvz00gbv4b";
    };
    nativeBuildInputs = with python3Packages; [
      poetry-core
    ];
    postPatch = ''
      sed -i 's/PyYAML = .*/PyYAML = "*"/' pyproject.toml
      sed -i 's/loguru = .*/loguru = "*"/' pyproject.toml
    '';
    propagatedBuildInputs = with python3Packages; [
      loguru
      tqdm
      python-dateutil
      pyyaml
    ];
    doCheck = false;
  };

  item-synchronizer = python3Packages.buildPythonPackage rec {
    pname = "item-synchronizer";
    version = "1.1.5";
    format = "pyproject";
    src = fetchPypi {
      pname = "item_synchronizer";
      inherit version;
      sha256 = "0gi0nlqn09hgls155528brv5bzay5yf9rjilvblx8kw4gqn41all";
    };
    nativeBuildInputs = with python3Packages; [
      poetry-core
    ];
    postPatch = ''
      sed -i 's/bidict = .*/bidict = "*"/' pyproject.toml
      sed -i 's/bubop = .*/bubop = "*"/' pyproject.toml
    '';
    propagatedBuildInputs = with python3Packages; [
      bubop
      bidict
    ];
    doCheck = false;
  };

  taskw-ng = python3Packages.buildPythonPackage rec {
    pname = "taskw-ng";
    version = "0.2.7";
    format = "wheel";
    src = python3Packages.fetchPypi {
      pname = "taskw_ng";
      inherit version;
      format = "wheel";
      sha256 = "1si1lyjvylx4l84z1ny5dwainnadxappssnl1bz2z6cy9d06p5fv";
      dist = "py3";
      python = "py3";
    };
    propagatedBuildInputs = with python3Packages; [
      six
      python-dateutil
      pytz
    ];
    doCheck = false;
  };
in
  python3Packages.buildPythonApplication rec {
    pname = "syncall";
    version = "1.8.5";
    format = "pyproject";

    src = fetchPypi {
      inherit pname version;
      sha256 = "0xjl0k8byj3ps5fi80wxqcjzhpv0xmfrh51040zdx8nc5ifynzjc";
    };

    nativeBuildInputs = with python3Packages; [
      poetry-core
      poetry-dynamic-versioning
    ];

    postPatch = ''
      sed -i 's/PyYAML = .*/PyYAML = "*"/' pyproject.toml
      sed -i 's/loguru = .*/loguru = "*"/' pyproject.toml
      sed -i 's/bidict = .*/bidict = "*"/' pyproject.toml
      sed -i '/typing = .*/d' pyproject.toml
    '';

    propagatedBuildInputs = with python3Packages; [
      pyyaml
      bidict
      click
      google-api-python-client
      google-auth-oauthlib
      loguru
      python-dateutil
      rfc3339
      item-synchronizer
      bubop
      taskw-ng
      xdg
    ];

    doCheck = false;

    meta = with lib; {
      description = "Versatile bi-directional synchronization tool";
      homepage = "https://github.com/bergercookie/syncall";
      license = licenses.mit;
    };
  }
