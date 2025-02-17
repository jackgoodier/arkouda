
module MsgProcessing
{
    use ServerConfig;

    use Time only;
    use Math only;
    use Reflection;
    use Errors;
    use Logging;
    use Memory;
    
    use MultiTypeSymbolTable;
    use MultiTypeSymEntry;
    use ServerErrorStrings;

    use AryUtil;
    
    public use OperatorMsg;
    public use RandMsg;
    public use IndexingMsg;
    public use UniqueMsg;
    public use In1dMsg;
    public use HistogramMsg;
    public use ArgSortMsg;
    public use SortMsg;
    public use ReductionMsg;
    public use FindSegmentsMsg;
    public use EfuncMsg;
    public use ConcatenateMsg;
    public use SegmentedMsg;
    public use JoinEqWithDTMsg;
    public use RegistrationMsg;
    public use ArraySetopsMsg;
    public use KExtremeMsg;
    public use CastMsg;
    public use BroadcastMsg;
    public use FlattenMsg;
    
    const mpLogger = new Logger();
    
    if v {
        mpLogger.level = LogLevel.DEBUG;
    } else {
        mpLogger.level = LogLevel.INFO;
    }
    
    /* 
    Parse, execute, and respond to a create message 

    :arg : payload
    :type bytes: containing (dtype,size)

    :arg st: SymTab to act on
    :type st: borrowed SymTab 

    :returns: (string) response message
    */
    proc createMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        var repMsg: string; // response message
        // split request into fields
        var (dtypestr, sizestr) = payload.decode().splitMsgToTuple(2);
        var dtype = str2dtype(dtypestr);
        var size = try! sizestr:int;
        if (dtype == DType.UInt8) || (dtype == DType.Bool) {
          overMemLimit(size);
        } else {
          overMemLimit(8*size);
        }
        // get next symbol name
        var rname = st.nextName();
        
        // if verbose print action
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(), 
            "cmd: %s dtype: %s size: %i new pdarray name: %s".format(
                                                     cmd,dtype2str(dtype),size,rname));
        // create and add entry to symbol table
        st.addEntry(rname, size, dtype);
        // if verbose print result
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(), 
                                    "created the pdarray %s".format(st.attrib(rname)));
                                    
        // response message                                    
        return try! "created " + st.attrib(rname);
    }

    /* 
    Parse, execute, and respond to a delete message 

    :arg reqMsg: request containing (cmd,name)
    :type reqMsg: string 

    :arg st: SymTab to act on
    :type st: borrowed SymTab 

    :returns: (string) response message
    */
    proc deleteMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        var repMsg: string; // response message
        // split request into fields
        var (name) = payload.decode().splitMsgToTuple(1);
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(), 
                                                        "cmd: %s name: %s".format(cmd,name));
        // delete entry from symbol table
        st.deleteEntry(name);
        return try! "deleted %s".format(name);
    }

    /* 
    Clear all unregistered symbols and associated data from sym table
    
    :arg reqMsg: request containing (cmd)
    :type reqMsg: string 

    :arg st: SymTab to act on
    :type st: borrowed SymTab 

    :returns: (string)
     */
    proc clearMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        var repMsg: string; // response message
        var (_) = payload.decode().splitMsgToTuple(1); // split request into fields
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(), "cmd: %s".format(cmd));
        st.clear();
        return "success";
    }

    /* 
    Takes the name of data referenced in a msg and searches for the name in the provided sym table.
    Returns a string of info for the sym entry that is mapped to the provided name.

    :arg reqMsg: request containing (cmd,name)
    :type reqMsg: string 

    :arg st: SymTab to act on
    :type st: borrowed SymTab 

    :returns: (string)
     */
    proc infoMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        var repMsg: string; // response message
        // split request into fields
        var (name) = payload.decode().splitMsgToTuple(1);
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(), 
                                                         "cmd: %s name: %s".format(cmd,name));
        // if name == "__AllSymbols__" passes back info on all symbols
        return st.info(name);
    }
    
    /* 
    query server configuration...
    
    :arg reqMsg: request containing (cmd)
    :type reqMsg: string 

    :arg st: SymTab to act on
    :type st: borrowed SymTab 

    :returns: (string)
     */
    proc getconfigMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        var repMsg: string; // response message
        var (_) = payload.decode().splitMsgToTuple(1); // split request into fields
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),"cmd: %s".format(cmd));
        return getConfig();
    }

    /* 
    query server total memory allocated or symbol table data memory
    
    :arg reqMsg: request containing (cmd)
    :type reqMsg: string 

    :arg st: SymTab to act on
    :type st: borrowed SymTab 

    :returns: (string)
     */
    proc getmemusedMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        var repMsg: string; // response message
        var (_) = payload.decode().splitMsgToTuple(1); // split request into fields
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),"cmd: %s".format(cmd));
        if (memTrack) {
            return (memoryUsed():uint * numLocales:uint):string;
        }
        else {
            return st.memUsed():string;
        }
    }
    
    /* 
    Response to __str__ method in python str convert array data to string 

    :arg reqMsg: request containing (cmd,name)
    :type reqMsg: string 

    :arg st: SymTab to act on
    :type st: borrowed SymTab 

    :returns: (string)
   */
    proc strMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        var repMsg: string; // response message
        // split request into fields
        var (name, ptstr) = payload.decode().splitMsgToTuple(2);
        var printThresh = try! ptstr:int;
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(), 
                                              "cmd: %s name: %s threshold: %i".format(
                                               cmd,name,printThresh));       
        return st.datastr(name,printThresh);
    }

    /* Response to __repr__ method in python.
       Repr convert array data to string 
       
       :arg reqMsg: request containing (cmd,name)
       :type reqMsg: string 

       :arg st: SymTab to act on
       :type st: borrowed SymTab 

       :returns: (string)
      */ 
    proc reprMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        var repMsg: string; // response message
        // split request into fields
        var (name, ptstr) = payload.decode().splitMsgToTuple(2);
        var printThresh = try! ptstr:int;
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                              "cmd: %s name: %s threshold: %i".format(
                                              cmd,name,printThresh));
        return st.datarepr(name,printThresh);
    }


    /*
    Creates a sym entry with distributed array adhering to the Msg parameters (start, stop, stride)

    :arg reqMsg: request containing (cmd,start,stop,stride)
    :type reqMsg: string 

    :arg st: SymTab to act on
    :type st: borrowed SymTab 

    :returns: (string)
    */
    proc arangeMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        var repMsg: string; // response message
//        var (cmd, start, stop, stride) = try! (reqMsg.splitMsgToTuple(4): (string, int, int, int));
        var (startstr, stopstr, stridestr) = payload.decode().splitMsgToTuple(3);
        var start = try! startstr:int;
        var stop = try! stopstr:int;
        var stride = try! stridestr:int;
        // compute length
        var len = (stop - start + stride - 1) / stride;
        overMemLimit(8*len);
        // get next symbol name
        var rname = st.nextName();
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(), 
                       "cmd: %s start: %i stop: %i stride: %i : len: %i rname: %s".format(
                        cmd, start, stop, stride, len, rname));
        
        var t1 = Time.getCurrentTime();
        var e = st.addEntry(rname, len, int);
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                      "alloc time = %i sec".format(Time.getCurrentTime() - t1));

        t1 = Time.getCurrentTime();
        ref ea = e.a;
        ref ead = e.aD;
        forall (ei, i) in zip(ea,ead) {
            ei = start + (i * stride);
        }
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                      "compute time = %i sec".format(Time.getCurrentTime() - t1));

        return try! "created " + st.attrib(rname);
    }            

    /* 
    Creates a sym entry with distributed array adhering to the Msg parameters (start, stop, len)

    :arg reqMsg: request containing (cmd,start,stop,len)
    :type reqMsg: string 

    :arg st: SymTab to act on
    :type st: borrowed SymTab 

    :returns: (string)
    */
    proc linspaceMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        var repMsg: string; // response message
//        var (start, stop, len) = try! (payload.decode().splitMsgToTuple(3): (real, real, int));
        var (startstr, stopstr, lenstr) = payload.decode().splitMsgToTuple(3);
        var start = try! startstr:real;
        var stop = try! stopstr:real;
        var len = try! lenstr:int;
        // compute stride
        var stride = (stop - start) / (len-1);
        overMemLimit(8*len);
        // get next symbol name
        var rname = st.nextName();
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                        "cmd: %s start: %r stop: %r len: %i stride: %r rname: %s".format(
                         cmd, start, stop, len, stride, rname));

        var t1 = Time.getCurrentTime();
        var e = st.addEntry(rname, len, real);
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                      "alloc time = %i".format(Time.getCurrentTime() - t1));

        t1 = Time.getCurrentTime();
        ref ea = e.a;
        ref ead = e.aD;
        forall (ei, i) in zip(ea,ead) {
            ei = start + (i * stride);
        }
        ea[0] = start;
        ea[len-1] = stop;
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                   "compute time = %i".format(Time.getCurrentTime() - t1));

        return try! "created " + st.attrib(rname);
    }

    /* 
    Sets all elements in array to a value (broadcast) 

    :arg reqMsg: request containing (cmd,name,dtype,value)
    :type reqMsg: string 

    :arg st: SymTab to act on
    :type st: borrowed SymTab 

    :returns: (string)
    :throws: `UndefinedSymbolError(name)`
    */
    proc setMsg(cmd: string, payload: bytes, st: borrowed SymTab): string throws {
        param pn = Reflection.getRoutineName();
        var repMsg: string; // response message
        var (name, dtypestr, value) = payload.decode().splitMsgToTuple(3);
        var dtype = str2dtype(dtypestr);

        var gEnt: borrowed GenSymEntry = st.lookup(name);

        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                      "cmd: %s value: %s in pdarray %s".format(cmd,name,st.attrib(name)));

        select (gEnt.dtype, dtype) {
            when (DType.Int64, DType.Int64) {
                var e = toSymEntry(gEnt,int);
                var val: int = try! value:int;
                e.a = val;
                repMsg = try! "set %s to %t".format(name, val);
            }
            when (DType.Int64, DType.Float64) {
                var e = toSymEntry(gEnt,int);
                var val: real = try! value:real;
                mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                        "cmd: %s name: %s to val: %t".format(cmd,name,val:int));
                e.a = val:int;
                repMsg = try! "set %s to %t".format(name, val:int);
            }
            when (DType.Int64, DType.Bool) {
                var e = toSymEntry(gEnt,int);
                value = value.replace("True","true");
                value = value.replace("False","false");
                var val: bool = try! value:bool;
                mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                        "cmd: %s name: %s to val: %t".format(cmd,name,val:int));
                e.a = val:int;
                repMsg = try! "set %s to %t".format(name, val:int);
            }
            when (DType.Float64, DType.Int64) {
                var e = toSymEntry(gEnt,real);
                var val: int = try! value:int;
                mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                      "cmd: %s name: %s to value: %t".format(cmd,name,val:real));
                e.a = val:real;
                repMsg = try! "set %s to %t".format(name, val:real);
            }
            when (DType.Float64, DType.Float64) {
                var e = toSymEntry(gEnt,real);
                var val: real = try! value:real;
                mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                           "cmd: %s name; %s to value: %t".format(cmd,name,val));
                e.a = val;
                repMsg = try! "set %s to %t".format(name, val);
            }
            when (DType.Float64, DType.Bool) {
                var e = toSymEntry(gEnt,real);
                value = value.replace("True","true");
                value = value.replace("False","false");                
                var val: bool = try! value:bool;
                mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                       "cmd: %s name: %s to value: %t".format(cmd,name,val:real));
                e.a = val:real;
                repMsg = try! "set %s to %t".format(name, val:real);
            }
            when (DType.Bool, DType.Int64) {
                var e = toSymEntry(gEnt,bool);
                var val: int = try! value:int;
                mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                       "cmd: %s name: %s to value: %t".format(cmd,name,val:bool));
                e.a = val:bool;
                repMsg = try! "set %s to %t".format(name, val:bool);
            }
            when (DType.Bool, DType.Float64) {
                var e = toSymEntry(gEnt,int);
                var val: real = try! value:real;
                mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                      "cmd: %s name: %s to  value: %t".format(cmd,name,val:bool));
                e.a = val:bool;
                repMsg = try! "set %s to %t".format(name, val:bool);
            }
            when (DType.Bool, DType.Bool) {
                var e = toSymEntry(gEnt,bool);
                value = value.replace("True","true");
                value = value.replace("False","false");
                var val: bool = try! value:bool;
                mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                            "cmd: %s name: %s to value: %t".format(cmd,name,val));
                e.a = val;
                repMsg = try! "set %s to %t".format(name, val);
            }
            otherwise {
                mpLogger.error(getModuleName(),getRoutineName(),
                                               getLineNumber(),"dtype: %s".format(dtypestr));
                return unrecognizedTypeError(pn,dtypestr);
            }
        }
        mpLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),repMsg);
        return repMsg;
    }
}
