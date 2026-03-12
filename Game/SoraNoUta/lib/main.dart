import 'package:sakiengine/sakiengine.dart';
import 'package:soranouta_project/soranouta_project.dart';

Future<void> main() async {
  registerProjectModule('soranouta', createProjectModule);
  await runSakiEngine(projectName: 'SoraNoUta', appName: 'SoraNoUta');
}
