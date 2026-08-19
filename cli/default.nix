{ lib, python3 }:

python3.pkgs.buildPythonApplication {
  pname = "sovereign-host-cli";
  version = "0.1.0";
  pyproject = true;
  src = ./.;
  nativeBuildInputs = with python3.pkgs; [ setuptools wheel ];
  propagatedBuildInputs = with python3.pkgs; [ click tabulate ];
  pythonImportsCheck = [ "sovereign_cli" ];
  meta = {
    description = "nixos-sovereign-host CLI — status, health and management for the declarative self-hosting stack";
    license = lib.licenses.mit;
    maintainers = [ ];
    homepage = "https://github.com/EnovaMaker/nixos-sovereign-host";
  };
}