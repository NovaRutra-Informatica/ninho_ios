import SwiftUI

struct WidgetsGuideView: View {
    @EnvironmentObject private var store: NinhoStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 18) {
                    Image("owl").renderingMode(.original).resizable().scaledToFit().frame(width: 76, height: 90).accessibilityHidden(true)
                    Text("Um pedacinho do seu Ninho, sempre por perto.").font(.system(.title2, design: .serif))
                }
                if !store.widgetNotice.isEmpty {
                    Label(store.widgetNotice, systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(NinhoStyle.amber).ninhoCard()
                }
                VStack(alignment: .leading, spacing: 14) {
                    Label("Na tela de início", systemImage: "square.grid.2x2").font(.headline)
                    Text("1. Toque e segure um espaço vazio da tela de início do iPhone.")
                    Text("2. Toque em Editar e depois em Adicionar Widget.")
                    Text("3. Procure Ninho, escolha o widget e o tamanho e toque em Adicionar Widget.")
                    Text("4. Posicione onde quiser e conclua a edição.")
                }.ninhoCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("O que levar com você", systemImage: "flame.fill").font(.headline)
                    Text("Sequência: seu foguinho e os dias de constância.")
                    Text("Hoje: minutos estudados, meta diária e revisões.")
                    Text("Foco: um atalho para preparar seu próximo bloco.")
                    Text("Toque no widget para abrir a tela correspondente. A sessão de foco só começa quando você tocar em Começar dentro do Ninho.").font(.subheadline).foregroundStyle(.secondary)
                }.ninhoCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("Na tela bloqueada", systemImage: "lock.iphone").font(.headline)
                    Text("Toque e segure a tela bloqueada, escolha Personalizar e toque na área de widgets. Procure Ninho e escolha um dos formatos disponíveis.")
                    Text("Os números ficam visíveis onde você colocar o widget. Objetivos, respostas do perfil, nomes de matérias e materiais não aparecem nele.").font(.subheadline).foregroundStyle(.secondary)
                }.ninhoCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("Atalhos do iPhone", systemImage: "square.stack.3d.up").font(.headline)
                    Text("No aplicativo Atalhos, procure as ações do Ninho para abrir Foco e Revisões. Você também pode adicioná-las às suas rotinas pessoais.")
                    Text("O widget usa um resumo salvo pelo Ninho, sem carregar modelos de IA. O iOS controla quando atualiza; abrir o aplicativo atualiza os registros compartilhados.").font(.subheadline).foregroundStyle(.secondary)
                }.ninhoCard()
            }.padding(20)
        }.background(NinhoStyle.canvas).navigationTitle("Widgets e atalhos").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.widgets")
    }
}
