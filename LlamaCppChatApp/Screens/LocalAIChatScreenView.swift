//
//  LocalAIChatScreenView.swift
//  LlamaCppChatApp
//
//  Created by ikeuchi.ryuto on 2025/03/15.
//

import Foundation
import MarkdownUI
import SwiftUI

struct LocalAIChatScreenView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var llamaState = LlamaState()

    @State private var multiLineText = ""
    @State var userPrompt = ""
//    @State private var progress = 0.0
//    @State private var downloadTask: URLSessionDownloadTask?
//    @State private var observation: NSKeyValueObservation?

    @State private var messages: [ChatMessage] = [
        ChatMessage(content: "こんにちは", role: "user"),
        ChatMessage(content: "こんにちは!Phi-4-miniです。", role: "ai"),
    ]


    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                ScrollView(.vertical) {
                    ScrollViewReader { sp in
                        Group {
                            ForEach(messages) { message in
                                HStack {
                                    ChatBubble(message: message)
                                }
                            }
                        }.onChange(of: llamaState.output) { newOutput in
                            if let lastIndex = messages.indices.last,
                                messages[lastIndex].role == "ai"
                            {
                                messages[lastIndex].content = newOutput
                            }
                            sp.scrollTo("bottom")
                        }

                        Spacer().frame(width: 1, height: 1).id("bottom")
                    }
                }

                HStack {
                    TextField("メッセージを入力", text: $userPrompt).font(.title3)
                        .bold().onSubmit(generate)
                    Button(action: generate) {
                        Image(systemName: "mic.fill").foregroundStyle(.blue)
                            .frame(width: 24, height: 24)
                    }
                }.padding(.leading, 40).padding(.trailing, 32).padding(
                    .vertical, 28
                ).background(
                    Color.white
                ).cornerRadius(40).overlay(
                    RoundedRectangle(cornerRadius: 40).stroke(.white))

            }
            .padding(.horizontal, 60)
            .background(.BACKGROUND)
            .navigationBarTitle(
                llamaState.deviceStatus
            )
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .task {
            llamaState.load(modelName: "Phi-4-mini-instruct.Q8_0.gguf")
        }
    }

    private func generate() {
        Task {
            messages.append(ChatMessage(content: userPrompt, role: "user"))
            messages.append(ChatMessage(content: "", role: "ai"))
            await llamaState.complete(text: userPrompt)
            userPrompt = ""
        }
    }

//    func getFileURL(filename: String) -> URL {
//        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[
//            0
//        ].appendingPathComponent(filename)
//    }

//    private func load() {
//        let targetModel = llamaState.downloadedModels.first(where: { $0.filename == "Phi-4-mini-instruct.Q8_0.gguf" })
//        print(targetModel)
//        let fileURL = getFileURL(filename: targetModel!.filename)
//        if !FileManager.default.fileExists(atPath: fileURL.path) {
//            download()
//            return
//        }
//        do {
//            try llamaState.loadModel(modelUrl: fileURL)
//        } catch let err {
//            print("Error: \(err.localizedDescription)")
//        }
//    }

//    private func download() {
//        //        status = "downloading"
//        //        print("Downloading model \(modelName) from \(modelUrl)")
//        let targetModel = llamaState.downloadedModels.last
//        let modelUrl = targetModel!.url
//        let modelName = targetModel!.name
//        let filename = targetModel!.filename
//        guard let url = URL(string: modelUrl) else { return }
//        let fileURL = getFileURL(filename: filename)
//        print(targetModel)
//        downloadTask = URLSession.shared.downloadTask(with: url) {
//            temporaryURL, response, error in
//            if let error = error {
//                print("Error: \(error.localizedDescription)")
//                return
//            }
//
//            guard let response = response as? HTTPURLResponse,
//                (200...299).contains(response.statusCode)
//            else {
//                print("Server error!")
//                return
//            }
//
//            do {
//                if let temporaryURL = temporaryURL {
//                    try FileManager.default.copyItem(
//                        at: temporaryURL, to: fileURL)
//                    print("Writing to \(filename) completed")
//
//                    llamaState.cacheCleared = false
//
//                    let model = Model(
//                        name: modelName, url: modelUrl, filename: filename,
//                        status: "downloaded")
//                    llamaState.downloadedModels.append(model)
//                    //                    status = "downloaded"
//                }
//            } catch let err {
//                print("Error: \(err.localizedDescription)")
//            }
//        }
//
//        observation = downloadTask?.progress.observe(\.fractionCompleted) {
//            progress, _ in
//            self.progress = progress.fractionCompleted
//            print(self.progress)
//        }
//
//        downloadTask?.resume()
//    }

}

#Preview {
    LocalAIChatScreenView()
}

struct ChatMessage: Identifiable {
    var id = UUID()
    var content: String
    var role: String
}

struct ChatBubble: View {
    var message: ChatMessage

    var body: some View {
        if message.role == "user" {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(message.content)
                        .padding(16)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 16,
                                bottomLeadingRadius: 16,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 16,
                                style: .continuous
                            ).foregroundStyle(.white)
                        )
                        .foregroundColor(.blue)
                        .fontWeight(.bold)
                    Text("Sent: \(getMessageSentTime())")
                        .font(.system(size: 8, weight: .medium))
                }
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phi-4-mini")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.bottom, 4)
                    HStack {
                        Image("Phi4MiniIcon").resizable().scaledToFit().frame(
                            width: 50, height: 50
                        ).clipShape(
                            Circle()
                        )
                        Markdown(message.content)
                            .markdownBlockStyle(\.heading1) { configuration in
                                configuration.label
                                    .padding(8)
                                    .markdownMargin(top: 0, bottom: 32)
                                    .markdownTextStyle {
                                        FontSize(24)
                                        FontWeight(.bold)
                                    }
                            }
                            .markdownBlockStyle(\.heading2) { configuration in
                                configuration.label
                                    .padding(8)
                                    .markdownMargin(top: 0, bottom: 16)
                                    .markdownTextStyle {
                                        FontSize(16)
                                        FontWeight(.bold)
                                    }
                            }
                            .markdownBlockStyle(\.heading3) { configuration in
                                configuration.label
                                    .markdownMargin(top: 16, bottom: 8)
                                    .markdownTextStyle {
                                        FontSize(18)
                                        FontWeight(.bold)
                                    }
                            }
                            .textSelection(.enabled)
                            .padding(16)
                            .background(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 16,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 16,
                                    topTrailingRadius: 16,
                                    style: .continuous
                                ).foregroundStyle(.white)
                            )
                    }
                }
                Spacer()
            }
        }
    }

    private func getMessageSentTime() -> String {
        let date = NSDate()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date as Date)
    }

}
