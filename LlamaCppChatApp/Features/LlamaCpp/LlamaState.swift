//
//  LlamaState.swift
//  LlamaCppChatApp
//
//  Created by ikeuchi.ryuto on 2025/03/15.
//

import Foundation

struct Model: Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var filename: String
    var status: String?
}

enum Status: String {
    case loading
    case loaded
    case downloading
    case running
    case finished
}

@MainActor
class LlamaState: ObservableObject {
    @Published var output = ""
    @Published var batchOutput: String = ""
    @Published var deviceStatus = ""
    @Published var downloadedModels: [Model] = []
    @Published var undownloadedModels: [Model] = []
    @Published var status = Status.loading
    @Published var progressTime: Double = 0

    let NS_PER_S = 1_000_000_000.0

    private var llamaContext: LlamaContext?
    private var selectedModel: Model?
    private var downloadTask: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?

    init() {
        loadModelsFromDisk()
        loadDefaultModels()
    }

    private func loadModelsFromDisk() {
        do {
            let documentsURL = getDocumentsDirectory()
            let modelURLs = try FileManager.default.contentsOfDirectory(
                at: documentsURL, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
            for modelURL in modelURLs {
                let modelName = modelURL.deletingPathExtension()
                    .lastPathComponent
                downloadedModels.append(
                    Model(
                        name: modelName, url: "",
                        filename: modelURL.lastPathComponent,
                        status: "downloaded"))
            }
        } catch {
            print("Error loading models from disk: \(error)")
        }
    }

    private func loadDefaultModels() {
        for model in defaultModels {
            let fileURL = getDocumentsDirectory().appendingPathComponent(
                model.filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {

            } else {
                var undownloadedModel = model
                undownloadedModel.status = "download"
                undownloadedModels.append(undownloadedModel)
            }
        }
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    private let defaultModels: [Model] = [
        Model(
            name: "Phi-4-mini-q8(Q8_0, 4.06 GiB)",
            url:
                "https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct.Q8_0.gguf?download=true",
            filename: "Phi-4-mini-instruct.Q8_0.gguf", status: "download"),
        Model(
            name: "Phi-4-mini-4bit(Q4_K_M, 2.5 GiB)",
            url:
                "https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf?download=true",
            filename: "Phi-4-mini-instruct.Q4_K_M.gguf", status: "download"
        ),
        Model(
            name: "Phi-4-mini-16bit(Q16, 7.7 GiB)",
            url:
                "https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct.BF16.gguf?download=true",
            filename: "Phi-4-mini-instruct.Q16.gguf", status: "download"
        ),
    ]

    func loadModel(modelUrl: URL?) throws {
        if let modelUrl {
            deviceStatus += "Loading model...\n"
            llamaContext = try LlamaContext.create_context(
                path: modelUrl.path())
            deviceStatus += "Loaded model \(modelUrl.lastPathComponent)\n"

            // Assuming that the model is successfully loaded, update the downloaded models
            updateDownloadedModels(
                modelName: modelUrl.lastPathComponent, status: "downloaded")
        } else {
            deviceStatus += "Load a model from the list below\n"
        }
    }

    private func updateDownloadedModels(modelName: String, status: String) {
        undownloadedModels.removeAll { $0.name == modelName }
    }

    private func getFileURL(filename: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[
            0
        ].appendingPathComponent(filename)
    }

    private func download() {
        guard let selectedModel else { return }
        guard let url = URL(string: selectedModel.url) else { return }
        let fileURL = getFileURL(filename: selectedModel.filename)

        status = Status.downloading
        downloadTask = URLSession.shared.downloadTask(with: url) {
            temporaryURL, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }

            guard let response = response as? HTTPURLResponse,
                (200...299).contains(response.statusCode)
            else {
                print("Server error!")
                return
            }

            do {
                if let temporaryURL = temporaryURL {
                    try FileManager.default.copyItem(
                        at: temporaryURL, to: fileURL)
                    Task { @MainActor in
                        print(
                            "Writing to \(selectedModel.filename) completed"
                        )

                        let model = Model(
                            name: selectedModel.name,
                            url: selectedModel.url,
                            filename: selectedModel.filename,
                            status: "downloaded")
                        self.downloadedModels.append(model)
                        self.status = Status.loaded
                    }
                }
            } catch let err {
                print("Error: \(err.localizedDescription)")
            }
        }

        observation = downloadTask?.progress.observe(\.fractionCompleted) {
            progress, _ in
            Task { @MainActor in
                self.progressTime = progress.fractionCompleted
                print(self.progressTime)
            }
        }

        downloadTask?.resume()
    }

    func load(modelName: String) {
        selectedModel = defaultModels.first(where: {
            $0.filename == modelName
        })

        let fileURL = getFileURL(filename: selectedModel!.filename)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            download()
            return
        }

        do {
            try loadModel(modelUrl: fileURL)
        } catch let err {
            print("Error: \(err.localizedDescription)")
        }
    }

    func complete(text: String) async {
        guard let llamaContext else {
            return
        }

        let t_start = DispatchTime.now().uptimeNanoseconds
        await llamaContext.completion_init(text: text)
        let t_heat_end = DispatchTime.now().uptimeNanoseconds
        let t_heat = Double(t_heat_end - t_start) / NS_PER_S
        output = ""
        batchOutput = ""

        Task.detached {
            while await !llamaContext.is_done {
                let result = await llamaContext.completion_loop()
                await MainActor.run {
                    self.output += "\(result)"
                }
            }

            let t_end = DispatchTime.now().uptimeNanoseconds
            let t_generation = Double(t_end - t_heat_end) / self.NS_PER_S
            let tokens_per_second =
                Double(await llamaContext.n_len) / t_generation

            await llamaContext.clear()
            await MainActor.run {
                self.batchOutput = self.output
                self.deviceStatus = """
                    Heat up took \(t_heat)s Generated \(t_generation) s\n
                    """
            }
        }
    }

    //    func bench() async {
    //        guard let llamaContext else {
    //            return
    //        }
    //
    //        messageLog += "\n"
    //        messageLog += "Running benchmark...\n"
    //        messageLog += "Model info: "
    //        messageLog += await llamaContext.model_info() + "\n"
    //
    //        let t_start = DispatchTime.now().uptimeNanoseconds
    //        let _ = await llamaContext.bench(pp: 8, tg: 4, pl: 1)  // heat up
    //        let t_end = DispatchTime.now().uptimeNanoseconds
    //
    //        let t_heat = Double(t_end - t_start) / NS_PER_S
    //        messageLog += "Heat up time: \(t_heat) seconds, please wait...\n"
    //
    //        // if more than 5 seconds, then we're probably running on a slow device
    //        if t_heat > 5.0 {
    //            messageLog += "Heat up time is too long, aborting benchmark\n"
    //            return
    //        }
    //
    //        let result = await llamaContext.bench(pp: 512, tg: 128, pl: 1, nr: 3)
    //
    //        messageLog += "\(result)"
    //        messageLog += "\n"
    //    }
    //
    //    func clear() async {
    //        guard let llamaContext else {
    //            return
    //        }
    //
    //        await llamaContext.clear()
    //        messageLog = ""
    //        deviceStatus = ""
    //    }
}
