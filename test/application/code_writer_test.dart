import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/code_writer.dart';

void main() {
  test('quita los bloques ``` que añade la IA', () {
    expect(cleanCode('```python\nprint(1)\n```'), 'print(1)\n');
    expect(cleanCode('Aquí tienes:\n```js\nconsole.log(1)\n```\nListo'),
        'console.log(1)\n');
    expect(cleanCode('print(2)'), 'print(2)\n');
  });

  test('nombre del archivo a partir de la descripción', () {
    expect(codeFileName('sumar', 'python'), 'sumar.py');
    expect(codeFileName('pida dos números y los multiplique', 'python'),
        'pida_dos_numeros.py');
    expect(codeFileName('cuente del 1 al 10', 'javascript'), 'cuente_del_1.js');
    expect(codeFileName('¿?', 'bash'), 'script.sh');
  });
}
