import "dart:io";

import "package:dart_api_service/dart_api_service.dart";

void main() {
  var awesome = Awesome();
  if (awesome.isAwesome) {
    exit(0);
  }

  exit(1);
}
