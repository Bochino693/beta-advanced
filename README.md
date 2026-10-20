# Strike Kids — versão OpenGL ES 3 (Godot 4) · boliche infantil 3D (Bob & Mia)

Versão **ALTA** do Strike Kids, em **Godot 4.6.1** (renderizador Compatibility, OpenGL ES 3,
física Jolt), com o **cenário COMPLETO** como padrão (chão e céu desenhados pixel a pixel,
toda a decoração com contornos e a neblina de profundidade). É para TV Boxes com
**OpenGL ES 3** (SmartPro/Mali-G31, TX9 Pro com S912, RK3566, S905X4…). No menu do
operador, "Cenário (fundo)" **LEVE** deixa o jogo leve para a SmartPro.

A **edição OpenGL ES 2.0** (Godot 3.6) fica no repositório
[`beta`](https://github.com/Bochino693/beta). Ela é para a TX9 comum, que tem
Mali-450/400 e não roda o Godot 4.

Jogo de boliche infantil para máquina arcade de **5 sensores**: mascotes fofinhos (Bob, o
cachorrinho, e Mia, a gatinha) com uma **roupinha 3D para cada fase** (piratas no Fundo do
Mar, dinossaurinhos na Selva, astronautas no Espaço, boné de hélice no Parque), **fases
sorteadas**, sol e lua com rostinho, pinos com física de verdade, máquina de pinos com
alçapão e navio pirata no Fundo do Mar.

- Projeto Godot: [`strike-kids/`](strike-kids/) — abra o `project.godot` no Godot 4.6.1 e aperte F5.
- Como testar, gerar o APK, as TV Boxes que rodam e operar a máquina: [`strike-kids/LEIA-ME.txt`](strike-kids/LEIA-ME.txt)
- Documento do jogo: [`strike-kids/docs/DOCUMENTO_DO_JOGO.md`](strike-kids/docs/DOCUMENTO_DO_JOGO.md)
- O fundo pode ser trocado na própria máquina (menu do operador > "Cenário (fundo)"):
  o padrão desta versão fica em `strike/video/cenario="completo"` no `project.godot`.
