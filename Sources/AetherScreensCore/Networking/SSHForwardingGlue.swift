//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See Resources/ThirdPartyNotices/SwiftNIO-SSH-LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

final class SSHForwardingGlue {
    private var partner: SSHForwardingGlue?

    private var context: ChannelHandlerContext?

    private var pendingRead: Bool = false
    private var pendingWrites = 0
    private var closeRequested = false
    private var outputCloseRequested = false

    private init() {}
}

extension SSHForwardingGlue {
    static func matchedPair() -> (SSHForwardingGlue, SSHForwardingGlue) {
        let first = SSHForwardingGlue()
        let second = SSHForwardingGlue()

        first.partner = second
        second.partner = first

        return (first, second)
    }
}

extension SSHForwardingGlue {
    private func partnerWrite(_ data: NIOAny) {
        guard let context = self.context, !closeRequested else { return }
        pendingWrites += 1
        let promise = context.eventLoop.makePromise(of: Void.self)
        promise.futureResult.whenComplete { [weak self] _ in
            guard let self else { return }
            self.pendingWrites -= 1
            self.finishRequestedClose()
        }
        context.write(data, promise: promise)
    }

    private func partnerFlush() {
        self.context?.flush()
    }

    private func partnerWriteEOF() {
        outputCloseRequested = true
        self.context?.flush()
        finishRequestedClose()
    }

    private func partnerCloseFull() {
        closeRequested = true
        self.context?.flush()
        finishRequestedClose()
    }

    private func finishRequestedClose() {
        guard pendingWrites == 0 else { return }
        if closeRequested { self.context?.close(promise: nil) }
        else if outputCloseRequested {
            outputCloseRequested = false
            self.context?.close(mode: .output, promise: nil)
        }
    }

    private func partnerBecameWritable() {
        if self.pendingRead {
            self.pendingRead = false
            self.context?.read()
        }
    }

    private var partnerWritable: Bool {
        self.context?.channel.isWritable ?? false
    }
}

extension SSHForwardingGlue: ChannelDuplexHandler {
    typealias InboundIn = NIOAny
    typealias OutboundIn = NIOAny
    typealias OutboundOut = NIOAny

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context

        // It's possible our partner asked if we were writable, before, and we couldn't answer.
        // Consider updating it.
        if context.channel.isWritable {
            self.partner?.partnerBecameWritable()
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        self.partner = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.partner?.partnerWrite(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        self.partner?.partnerFlush()
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.partner?.partnerCloseFull()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event {
            // We have read EOF.
            self.partner?.partnerWriteEOF()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.partner?.partnerCloseFull()
        context.close(promise: nil)
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable {
            self.partner?.partnerBecameWritable()
        }
    }

    func read(context: ChannelHandlerContext) {
        if let partner = self.partner, partner.partnerWritable {
            context.read()
        } else {
            self.pendingRead = true
        }
    }
}
