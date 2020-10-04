//public extension LeafRenderer {
//    func render<E>(_ name: String,
//                   _ context: E) -> EventLoopFuture<ByteBuffer> where E: Encodable {
//        
//        
////        let data: [String: LeafData]
////        do { data = try LeafEncoder().encode(context) }
////        catch { return eventLoop.makeFailedFuture(error) }
////
////        return render(path: name, context: data).map { View(data: $0) }
//    }
//
//}
