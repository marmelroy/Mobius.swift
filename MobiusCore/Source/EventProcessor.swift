// Copyright (c) 2019 Spotify AB.
//
// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import Foundation

/// Internal class that manages the atomic state updates and notifications of model changes when processing of events via
/// the Update function.
class EventProcessor<Model, Event, Effect>: Disposable, CustomDebugStringConvertible {
    let update: Update<Model, Event, Effect>
    let publisher: ConnectablePublisher<Next<Model, Effect>>

    private let queue: DispatchQueue

    private var currentModel: Model?
    private var queuedEvents = [Event]()

    public var debugDescription: String {
        let modelDescription: String
        if let currentModel = currentModel {
            modelDescription = String(reflecting: currentModel)
        } else {
            modelDescription = "nil"
        }
        return "<\(modelDescription), \(queuedEvents)>"
    }

    init(
        update: @escaping Update<Model, Event, Effect>,
        publisher: ConnectablePublisher<Next<Model, Effect>>,
        queue: DispatchQueue
    ) {
        self.update = update
        self.publisher = publisher
        self.queue = queue
    }

    func start(from first: First<Model, Effect>) {
        queue.sync(flags: .barrier) {
            currentModel = first.model

            publisher.post(Next.next(first.model, effects: first.effects))

            for event in queuedEvents {
                accept(event)
            }

            queuedEvents = []
        }
    }

    func accept(_ event: Event) {
        queue.async(flags: .barrier) {
            if let current = self.currentModel {
                let next = self.update(current, event)

                if let newModel = next.model {
                    self.currentModel = newModel
                }

                self.publisher.post(next)
            } else {
                self.queuedEvents.append(event)
            }
        }
    }

    func dispose() {
        publisher.dispose()
    }

    func readCurrentModel() -> Model? {
        return queue.sync { currentModel }
    }

    var latestModel: Model {
        guard let model = readCurrentModel() else {
            preconditionFailure("latestModel may only be invoked after start()")
        }
        return model
    }
}
