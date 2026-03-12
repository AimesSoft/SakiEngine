import 'package:sakiengine/sakiengine.dart';
import 'package:test_project/test_project.dart';

Future<void> main() async {
  registerProjectModule('test', createProjectModule);
  await runSakiEngine(
    projectName: 'test',
    appName: 'test',
  );
}
