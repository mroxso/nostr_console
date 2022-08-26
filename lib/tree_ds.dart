import 'dart:io';
import 'dart:convert';
import 'package:nostr_console/event_ds.dart';
import 'package:nostr_console/settings.dart';

typedef fTreeSelector = bool Function(Tree a);

bool selectAll(Tree t) {
  return true;
}

class Tree {
  Event             e;
  List<Tree>        children;
  Map<String, Tree> allChildEventsMap;
  List<String>      eventsWithoutParent;
  bool              whetherTopMost;
  Map<String, ChatRoom> chatRooms = {};
  Tree(this.e, this.children, this.allChildEventsMap, this.eventsWithoutParent, this.whetherTopMost, this.chatRooms);

  static const List<int>   typesInEventMap = [0, 1, 3, 7, 40, 42]; // 0 meta, 1 post, 3 follows list, 7 reactions

  // @method create top level Tree from events. 
  // first create a map. then process each element in the map by adding it to its parent ( if its a child tree)
  factory Tree.fromEvents(List<Event> events) {
    if( events.isEmpty) {
      return Tree(Event("","",EventData("non","", 0, 0, "", [], [], [], [[]], {}), [""], "[json]"), [], {}, [], false, {});
    }

    // create a map from list of events, key is eventId and value is event itself
    Map<String, Tree> tempChildEventsMap = {};
    events.forEach((event) { 
      // only add in map those kinds that are supported or supposed to be added ( 0 1 3 7 40)
      if( typesInEventMap.contains(event.eventData.kind)) {
        tempChildEventsMap[event.eventData.id] = Tree(event, [], {}, [], false, {}); 
      }
    });

    // this will become the children of the main top node. These are events without parents, which are printed at top.
    List<Tree>  topLevelTrees = [];

    List<String> tempWithoutParent = [];
    Map<String, ChatRoom> rooms = {};

    if( gDebug > 0) print("In from Events: size of tempChildEventsMap = ${tempChildEventsMap.length} ");

    tempChildEventsMap.forEach((key, value) {
      String eId = value.e.eventData.id;
      int    eKind = value.e.eventData.kind;

      if(eKind == 42) {
        String chatRoomId = value.e.eventData.getChatRoomId();
        if( chatRoomId != "") {
          if( rooms.containsKey(chatRoomId)) {
            if( gDebug > 0) print("Adding new message $key to a chat room $chatRoomId. ");
            addMessageToChannel(chatRoomId, eId, tempChildEventsMap, rooms);
            if( gDebug > 0) print("Added new message to a chat room $chatRoomId. ");
          } else {
            List<String> temp = [];
            temp.add(eId);
            //String name = json['name'];
            ChatRoom room = ChatRoom(chatRoomId, "", "", "", temp);
            rooms[chatRoomId] = room;
            if( gDebug > 0) print("Added new chat room object $chatRoomId and added message to it. ");
          }
        } else {
          if( gDebug > 0) print("Could not get chat room id for event $eId, its original json: ");
          if( gDebug > 0) print(value.e.originalJson);
        }
      }

      if(eKind == 40) {
        //print("Processing type 40");
        String chatRoomId = eId;
        try {
          dynamic json = jsonDecode(value.e.eventData.content);
          if( rooms.containsKey(chatRoomId)) {
            if( rooms[chatRoomId]?.name == "") {
              if( gDebug > 0) print('Added room name = ${json['name']} for $chatRoomId' );
              rooms[chatRoomId]?.name = json['name'];
            }
          } else {
            List<String> temp = [];
            String roomName = "", roomAbout = "";
            if(  json.containsKey('name') ) {
              roomName = json['name'];
            }
            
            if( json.containsKey('about')) {
              roomAbout = json['about'];
            }
            ChatRoom room = ChatRoom(chatRoomId, roomName, roomAbout, "", []);
            rooms[chatRoomId] = room;
            if( gDebug > 0) print("Added new chat room $chatRoomId with name ${json['name']} .");
          }
        } on Exception catch(e) {
          if( gDebug > 0) print("In From Event. Event type 40. Json Decode error for event id ${value.e.eventData.id}");
        }
      }

      // only posts, of kind 1, are added to the main tree structure
      if( eKind != 1) {
        return;
      }

      if(value.e.eventData.eTagsRest.isNotEmpty ) {
        // is not a parent, find its parent and then add this element to that parent Tree
        //stdout.write("added to parent a child\n");
        String id = key;
        String parentId = value.e.eventData.getParent();
        if( tempChildEventsMap.containsKey(parentId)) {
        }

        if( value.e.eventData.id == gCheckEventId) {
          if(gDebug > 0) print("In Tree FromEvents: got id: $gCheckEventId");
        }

        if(tempChildEventsMap.containsKey( parentId)) {
          if( tempChildEventsMap[parentId]?.e.eventData.kind != 1) { // since parent can only be a kind 1 event
            if( gDebug > 0) print("In Tree.fromEvents: got a kind 1 event whose parent is not a type 1 post: $id");
            return;
          }
          tempChildEventsMap[parentId]?.addChildNode(value); // in this if condition this will get called
        } else {
            if( gDebug > 0 && key == "e9c0c91d52a2cf000bb2460406139a99dd5b7823165be435e96433a600be8e41" || parentId == "f377a303a852c8821069714f43b4eef5e341c03892eacf49abb594660b2fbb00") {
              print (value.e.eventData.tags);
              print("In from json: newId = $key parentid = $parentId for event id = ${value.e.eventData.id}");
              print(tempChildEventsMap.containsKey(parentId));
              print("----------------------------------------------/constructor from json");
            }

           // in case where the parent of the new event is not in the pool of all events, 
           // then we create a dummy event and put it at top ( or make this a top event?) TODO handle so that this can be replied to, and is fetched
           Tree dummyTopNode = Tree(Event("","",
                                          EventData("Unk" ,gDummyAccountPubkey, value.e.eventData.createdAt , 1, "Unknown parent event", [], [], [], [[]], {}),
                                                    [""], "[json]"), 
                                    [], {}, [], false, {});
           dummyTopNode.addChildNode(value);
           tempWithoutParent.add(value.e.eventData.id); 
          
           // add the dummy evnets to top level trees, so that their real children get printed too with them
           // so no post is missed by reader
           topLevelTrees.add(dummyTopNode);
        }
      }
    }); // going over tempChildEventsMap 

    // add parent trees as top level child trees of this tree
    for( var value in tempChildEventsMap.values) {
        if( value.e.eventData.kind == 1 &&  value.e.eventData.eTagsRest.isEmpty) {  // only posts which are parents
            topLevelTrees.add(value);
        }
    }

    if( gDebug != 0) print("at end of tree from events: Total number of chat rooms: ${rooms.length}");
    if(gDebug != 0) print("number of events without parent in fromEvents = ${tempWithoutParent.length}");

    // create a dummy top level tree and then create the main Tree object
    Event dummy = Event("","",  EventData("non","", 0, 1, "Dummy Top event. Should not be printed.", [], [], [], [[]], {}), [""], "[json]");
    return Tree( dummy, topLevelTrees, tempChildEventsMap, tempWithoutParent, true, rooms);
  } // end fromEvents()

  /*
   * @insertEvents inserts the given new events into the tree, and returns the id the ones actually inserted so that they can be printed as notifications
   */
  List<String> insertEvents(List<Event> newEvents) {

    List<String> newEventsId = [];

    // add the event to the Tree
    newEvents.forEach((newEvent) { 
      // don't process if the event is already present in the map
      // this condition also excludes any duplicate events sent as newEvents
      if( allChildEventsMap.containsKey(newEvent.eventData.id)) {
        return;
      }

      // handle reaction events and return
      if( newEvent.eventData.kind == 7) {
        String reactedTo = processReaction(newEvent);
        
        if( reactedTo != "") {
          newEventsId.add(newEvent.eventData.id); // add here to process/give notification about this new reaction
          if(gDebug > 0) print("In insertEvents: got a new reaction by: ${newEvent.eventData.id} to $reactedTo");
        } else {
          if(gDebug > 0) print("In insertEvents: For new reaction ${newEvent.eventData.id} could not find reactedTo or reaction was already present by this reactor");
          return;
        }
      }

      // only kind 0, 1, 3, 7, 40, 42 events are added to map, return otherwise
      if( !typesInEventMap.contains(newEvent.eventData.kind) ) {
        return;
      }

      // experimental
      if( newEvent.eventData.pubkey == gRemoteAdminPubkey) {

      }

      // expand mentions ( and translate if flag is set)
      newEvent.eventData.translateAndExpandMentions();
      if( gDebug > 0) print("In insertEvents: adding event to main children map");

      allChildEventsMap[newEvent.eventData.id] = Tree(newEvent, [], {}, [], false, {});
      newEventsId.add(newEvent.eventData.id);
    });
    
    // now go over the newly inserted event, and add its to the tree. only for kind 1 events
    newEventsId.forEach((newId) {
      Tree? newTree = allChildEventsMap[newId]; // this should return true because we just inserted this event in the allEvents in block above
      if( newTree != null) {

        switch(newTree.e.eventData.kind) {
          case 1:
            // only kind 1 events are added to the overall tree structure
            if( newTree.e.eventData.eTagsRest.isEmpty) {
                // if its a new parent event, then add it to the main top parents ( this.children)
                children.add(newTree);
            } else {
                // if it has a parent , then add the newTree as the parent's child
                String parentId = newTree.e.eventData.getParent();
                if( gDebug > 0 && newId == "e9c0c91d52a2cf000bb2460406139a99dd5b7823165be435e96433a600be8e41" || parentId == "f377a303a852c8821069714f43b4eef5e341c03892eacf49abb594660b2fbb00") {
                  print (newTree.e.eventData.tags);
                  print("In from json: newId = $newId parentid = $parentId for event id = ${newTree.e.eventData.id}");
                  print(allChildEventsMap.containsKey(parentId));
                  print("----------------------------------------------/insert events");
                }
                if( allChildEventsMap.containsKey(parentId)) {
                  allChildEventsMap[parentId]?.addChildNode(newTree);
                } else {
                  // create top unknown parent and then add it
                  Tree dummyTopNode = Tree(Event("","",
                                                  EventData("Unk" ,gDummyAccountPubkey, newTree.e.eventData.createdAt , 1, "Unknown parent event", [], [], [], [[]], {}),
                                                            [""], "[json]"), 
                                                [], {}, [], false, {});
                  dummyTopNode.addChildNode(newTree);
                  children.add(dummyTopNode);
                }

            }
            break;
          case 42:
            // add 42 chat message event id to its chat room
            String channelId = newTree.e.eventData.getParent();
            if( channelId != "") {
              if( chatRooms.containsKey(channelId)) {
                if( gDebug > 0) print("added event to chat room in insert event");
                addMessageToChannel(channelId, newTree.e.eventData.id, allChildEventsMap, chatRooms);
              }
            } else {
              print("info: in insert events, could not find parent/channel id");
            }
            break;
          default: 
            break;
        }
      }
    });

    if(gDebug > 0) print("In insertEvents: Found new ${newEventsId.length} events. ");

    return newEventsId;
  }


  /*
   * @printNotifications Add the given events to the Tree, and print the events as notifications
   *                     It should be ensured that these are only kind 1 events
   */
  void printNotifications(List<String> newEventsId, String userName) {
    // remove duplicates
    Set temp = {};
    newEventsId.retainWhere((event) => temp.add(newEventsId));
    
    String strToWrite = "Notifications: ";
    int countNotificationEvents = 0;
    for( int i =0 ; i < newEventsId.length; i++) {
      int k = (allChildEventsMap[newEventsId[i]]?.e.eventData.kind??-1);
      if( k == 7 || k == 1 || k == 42 || k == 40) {
        countNotificationEvents++;
      }

      if(  allChildEventsMap.containsKey(newEventsId[i])) {
        if( gDebug > 0) print( "id = ${ (allChildEventsMap[newEventsId[i]]?.e.eventData.id??-1)}");
      } else {
        if( gDebug > 0) print( "Info: could not find event id in map."); // this wont later be processed
      }

    }
    // TODO don't print notifications for events that are too old

    if(gDebug > 0) print("Info: In printNotifications: newEventsId = $newEventsId count17 = $countNotificationEvents");
    
    if( countNotificationEvents == 0) {
      strToWrite += "No new replies/posts.\n";
      stdout.write("${getNumDashes(strToWrite.length - 1)}\n$strToWrite");
      stdout.write("Total posts  : ${count()}\n");
      stdout.write("Signed in as : $userName\n\n");
      return;
    }
    // TODO call count() less
    strToWrite += "Number of new replies/posts = ${newEventsId.length}\n";
    stdout.write("${getNumDashes(strToWrite.length -1 )}\n$strToWrite");
    stdout.write("Total posts  : ${count()}\n");
    stdout.write("Signed in as : $userName\n");
    stdout.write("\nHere are the threads with new replies or new likes: \n\n");
    
    List<Tree> topTrees = []; // collect all top tress to display in this list. only unique tress will be displayed
    newEventsId.forEach((eventID) { 
      
      Tree ?t = allChildEventsMap[eventID];
      if( t == null) {
        // ignore if not in Tree. Should ideally not happen. TODO write warning otherwise
        if( gDebug > 0) print("In printNotifications: Could not find event $eventID in tree");
        return;
      } else {
        switch(t.e.eventData.kind) {
          case 1:
            t.e.eventData.isNotification = true;
            Tree topTree = getTopTree(t);
            topTrees.add(topTree);
            break;
          case 7:
            Event event = t.e;
            if(gDebug >= 0) ("Got notification of type 7");
            String reactorId  = event.eventData.pubkey;
            int    lastEIndex = event.eventData.eTagsRest.length - 1;
            String reactedTo  = event.eventData.eTagsRest[lastEIndex];
            Event? reactedToEvent = allChildEventsMap[reactedTo]?.e;
            if( reactedToEvent != null) {
              Tree? reactedToTree = allChildEventsMap[reactedTo];
              if( reactedToTree != null) {
                reactedToTree.e.eventData.newLikes.add( reactorId);
                Tree topTree = getTopTree(reactedToTree);
                topTrees.add(topTree);
              } else {
                if(gDebug > 0) print("Could not find reactedTo tree");
              }
            } else {
              if(gDebug > 0) print("Could not find reactedTo event");
            }
            break;
          default:
            if(gDebug > 0) print("got an event thats not 1 or 7(reaction). its id = ${t.e.eventData.kind} count17 = $countNotificationEvents");
            break;
        }
      }
    });

    // remove duplicate top trees
    Set ids = {};
    topTrees.retainWhere((t) => ids.add(t.e.eventData.id));
    
    topTrees.forEach( (t) { t.printTree(0, 0, selectAll); });
    print("\n");
  }

  int printTree(int depth, var newerThan, fTreeSelector treeSelector) {

    int numPrinted = 0;


    if( !whetherTopMost) {
      e.printEvent(depth);
      numPrinted++;
    } else {
      depth = depth - 1;
      children.sort(sortTreeNewestReply); // sorting done only for top most threads. Lower threads aren't sorted so save cpu etc TODO improve top sorting
    }

    bool leftShifted = false;
    for( int i = 0; i < children.length; i++) {

      if(!whetherTopMost) {
        stdout.write("\n");  
        printDepth(depth+1);
        stdout.write("|\n");
      } else {
        // continue if this children isn't going to get printed anyway; selector is only called for top most tree
        if( !treeSelector(children[i])) {
          continue;
        }

        int newestChildTime = children[i].getMostRecentTime(0);
        DateTime dTime = DateTime.fromMillisecondsSinceEpoch(newestChildTime *1000);
        //print("comparing $newerThan with $dTime");
        if( dTime.compareTo(newerThan) < 0) {
          continue;
        }
        stdout.write("\n");  
        for( int i = 0; i < gapBetweenTopTrees; i++ )  { 
          stdout.write("\n"); 
        }
      }

      // if the thread becomes too 'deep' then reset its depth, so that its 
      // children will not be displayed too much on the right, but are shifted
      // left by about <leftShiftThreadsBy> places
      if( depth > maxDepthAllowed) {
        depth = maxDepthAllowed - leftShiftThreadsBy;
        printDepth(depth+1);
        stdout.write("<${getNumDashes((leftShiftThreadsBy + 1) * gSpacesPerDepth - 1)}+\n");        
        leftShifted = true;
      }

      numPrinted += children[i].printTree(depth+1, newerThan,  treeSelector);
      if( whetherTopMost && gDebug > 0) { 
        print("");
        print(children[i].getMostRecentTime(0));
        print("-----");
      }
      //if( gDebug > 0) print("at end for loop iteraion: numPrinted = $numPrinted");
    }

    if( leftShifted) {
      stdout.write("\n");
      printDepth(depth+1);
      print(">");
    }

    if( whetherTopMost) {
      print("\n\nTotal posts/replies printed: $numPrinted for last $gNumLastDays days");
    }
    return numPrinted;
  }

  void printAllChannelsInfo() {
    print("\n\nChannels/Rooms:");
    printUnderlined("      Channel/Room Name             Num of Messages            Latest Message           ");
    chatRooms.forEach((key, value) {
      String name = "";
      if( value.name == "") {
        name = value.chatRoomId.substring(0, 6);
      } else {
        name = "${value.name} ( ${value.chatRoomId.substring(0, 6)})";
      }

      int numMessages = value.messageIds.length;
      stdout.write("${name} ${getNumSpaces(32-name.length)}          $numMessages${getNumSpaces(12- numMessages.toString().length)}"); 
      List<String> messageIds = value.messageIds;
      for( int i = messageIds.length - 1; i >= 0; i++) {
        if( allChildEventsMap.containsKey(messageIds[i])) {
          Event? e = allChildEventsMap[messageIds[i]]?.e;
          if( e!= null) {
            //e.printEvent(0);
            stdout.write("${e.eventData.getAsLine()}");
            break; // print only one event, the latest one
          }
        }
      }
      print("");
    });
  }

  void printChannel(ChatRoom room)  {
    String displayName = room.chatRoomId;
    if( room.name != "") {
      displayName = "${room.name} ( ${displayName.substring(0, 6)} )";
    }

    int lenDashes = 10;
    String str = getNumSpaces(gNumLeftMarginSpaces + 10) + getNumDashes(lenDashes) + displayName + getNumDashes(lenDashes);
    print(" ${getNumSpaces(gNumLeftMarginSpaces + displayName.length~/2 + 4)}In Channel");
    print("\n$str\n");

      for(int i = 0; i < room.messageIds.length; i++) {
        String eId = room.messageIds[i];
        Event? e = allChildEventsMap[eId]?.e;
        if( e!= null) {
          e.printEvent(0);
          print("");
        }
      }
  }

  // shows the given channelId, where channelId is prefix-id or channel name as mentioned in room.name. returns full id of channel.
  String showChannel(String channelId) {
    
    for( String key in chatRooms.keys) {
      if( key.substring(0, channelId.length) == channelId ) {
        ChatRoom? room = chatRooms[key];
        if( room != null) {
          printChannel(room);
        }
        return key;
      }
    }

    // since channelId was not found in channel id, search for it in channel name
    for( String key in chatRooms.keys) {
        ChatRoom? room = chatRooms[key];
        if( room != null) {
          if( room.name.length < channelId.length) {
            continue;
          }
          if( gDebug > 0) print("room = ${room.name} channelId = $channelId");
          if( room.name.substring(0, channelId.length) == channelId ) {
            printChannel(room);
            return key;
          }
        }
    }
    return "";
  }

  // Write the tree's events to file as one event's json per line
  Future<void> writeEventsToFile(String filename) async {
    //print("opening $filename to write to");
    try {
      final File file         = File(filename);
      
      // empty the file
      await  file.writeAsString("", mode: FileMode.writeOnly).then( (file) => file);
      int        eventCounter = 0;
      String     nLinesStr    = "";
      int        countPosts   = 0;

      const int  numLinesTogether = 100; // number of lines to write in one write call
      int        linesWritten = 0;
      for( var k in allChildEventsMap.keys) {
        Tree? t = allChildEventsMap[k];
        if( t != null) {
          String line = "${t.e.originalJson}\n";
          nLinesStr += line;
          eventCounter++;
          if( t.e.eventData.kind == 1) {
            countPosts++;
          }
        }

        if( eventCounter % numLinesTogether == 0) {
          await  file.writeAsString(nLinesStr, mode: FileMode.append).then( (file) => file);
          nLinesStr = "";
          linesWritten += numLinesTogether;
        }
      }

      if(  eventCounter > linesWritten) {
        await  file.writeAsString(nLinesStr, mode: FileMode.append).then( (file) => file);
        nLinesStr = "";
      }

      print("\n\nWrote total $eventCounter events to file \"$gEventsFilename\" of which ${countPosts + 1} are posts.")  ; // TODO remove extra 1
    } on Exception catch (err) {
      print("Could not open file $filename.");
    }      
    
    return;
  }

  /*
   * @getTagsFromEvent Searches for all events, and creates a json of e-tag type which can be sent with event
   *                   Also adds 'client' tag with application name.
   * @parameter replyToId First few letters of an event id for which reply is being made
   */
  String getTagStr(String replyToId, String clientName) {
    String strTags = "";
    clientName = (clientName == "")? "nostr_console": clientName; // in case its empty 
    strTags += '["client","$clientName"]' ;

    if( replyToId.isEmpty) {
      return strTags;
    }

    // find the latest event with the given id; needs to be done because we allow user to refer to events with as few as 3 or so first letters
    // and only the event that's latest is considered as the intended recipient ( this is not perfect, but easy UI)
    int latestEventTime = 0;
    String latestEventId = "";
    for(  String k in allChildEventsMap.keys) {
      if( k.length >= replyToId.length && k.substring(0, replyToId.length) == replyToId) {
        if( ( allChildEventsMap[k]?.e.eventData.createdAt ?? 0) > latestEventTime ) {
          latestEventTime = allChildEventsMap[k]?.e.eventData.createdAt ?? 0;
          latestEventId = k;
        }
      }
    }

    // in case we are given valid length id, but we can't find the event in our internal db, then we just send the reply to given id
    if( latestEventId.isEmpty && replyToId.length == 64) {
      latestEventId = replyToId;  
    }

    // found the id of event we are replying to
    if( latestEventId.isNotEmpty) {
      String? pTagPubkey = allChildEventsMap[latestEventId]?.e.eventData.pubkey;
      if( pTagPubkey != null) {
        strTags += ',["p","$pTagPubkey"]';
      }
      String relay = getRelayOfUser(userPublicKey, pTagPubkey??"");
      relay = (relay == "")? defaultServerUrl: relay;
      String rootEventId = "";

      // nip 10: first e tag should be the id of the top/parent event. 2nd ( or last) e tag should be id of the event being replied to.
      Tree? t = allChildEventsMap[latestEventId];
      if( t != null) {
        Tree topTree = getTopTree(t);
        rootEventId = topTree.e.eventData.id;
        if( rootEventId != latestEventId) { // if the reply is to a top/parent event, then only one e tag is sufficient
          strTags +=  ',["e","$rootEventId"]';
        }
      }

      strTags +=  ',["e","$latestEventId","$relay"]';
    }
    return strTags;
  }
 
  int count() {
    int totalCount = 0;
    // ignore dummy events
    if(e.eventData.pubkey != gDummyAccountPubkey) {
      totalCount = 1;
    }
    for(int i = 0; i < children.length; i++) {
      totalCount += children[i].count(); // then add all the children
    }
    return totalCount;
  }

  void addChild(Event child) {
    Tree node;
    node = Tree(child, [], {}, [], false, {});
    children.add(node);
  }

  void addChildNode(Tree node) {
    children.add(node);
  }

  // for any tree node, returns its top most parent
  Tree getTopTree(Tree t) {
    while( true) {
      Tree? parent =  allChildEventsMap[ t.e.eventData.getParent()];
      if( parent != null) {
        t = parent;
      } else {
        break;
      }
    }
    return t;
  }

  // returns the time of the most recent comment
  int getMostRecentTime(int mostRecentTime) {
    int initial = mostRecentTime;
    if( children.isEmpty)   {
      return e.eventData.createdAt;
    }
    if( e.eventData.createdAt > mostRecentTime) {
      mostRecentTime = e.eventData.createdAt;
    }

    int mostRecentIndex = -1;
    for( int i = 0; i < children.length; i++) {
      int mostRecentChild = children[i].getMostRecentTime(mostRecentTime);
      if( mostRecentTime <= mostRecentChild) {
        if( gDebug > 0 && children[i].e.eventData.id == "970bbd22e63000dc1313867c61a50e0face728139afe6775fa9fe4bc61bdf664") {
          print("plantimals 970bbd22e63000dc1313867c61a50e0face728139afe6775fa9fe4bc61bdf664");
          print( "children[i].e.eventData. = ${children[i].e.eventData.createdAt} mostRecentChild = $mostRecentChild i = $i mostRecentIndex = $mostRecentIndex mostRecentTime = $mostRecentTime\n");
          printTree(0, 0, (a) => true);
          print("--------------");
        }

        mostRecentTime = mostRecentChild;
        mostRecentIndex = i;
      }
    }
    if( mostRecentIndex == -1) { 
      Tree top = getTopTree(this);
      if( gDebug > 0 ) {
        print('\nerror: returning newer child id = ${e.eventData.id}. e.eventData.createdAt = ${e.eventData.createdAt} num child = ${children.length} 1st child time = ${children[0].e.eventData.createdAt} mostRecentTime = $mostRecentTime initial time = $initial ');
        print("its top event time and id = time ${top.e.eventData.createdAt} id ${top.e.eventData.id} num tags = ${top.e.eventData.tags} num e tags = ${top.e.eventData.eTagsRest}\n");
        top.printTree(0,0, (a) => true);
        print("\n-----------------------------------------------------------------------\n");
      }
      // typically this should not happen. child nodes/events can't be older than parents 
      return e.eventData.createdAt;
    } else {
      return mostRecentTime;
    }
  }

/*
  // TODO
  // returns true if the treee or its children has a post or like by user; and notification flags are set for such events
  bool repliesAndLikes(String pubkey) {
    bool hasReacted = false;

    if( gReactions.containsKey(e.eventData.id)) {
      List<List<String>>? reactions = gReactions[e.eventData.id];
      if( reactions  != null) {
        for( int i = 0; i < reactions.length; i++) {
          if( reactions[i][0] == pubkey) {
            e.eventData.newLikes.add(pubkey);
            hasReacted = true;
            break;
          }
        }
      }
    }

    bool childMatches = false;
    for( int i = 0; i < children.length; i++ ) {
      if( children[i].hasUserPostAndLike(pubkey)) {
        childMatches = true;
      }
    }
    if( e.eventData.pubkey == pubkey) {
      e.eventData.isNotification = true;
      return true;
    }
    if( hasReacted || childMatches) {
      return true;
    }
    return false;
  } 
*/

  // returns true if the treee or its children has a post or like by user; and notification flags are set for such events
  bool hasUserPostAndLike(String pubkey) {
    bool hasReacted = false;

    if( gReactions.containsKey(e.eventData.id))  {
      List<List<String>>? reactions = gReactions[e.eventData.id];
      if( reactions  != null) {
        for( int i = 0; i < reactions.length; i++) {
          if( reactions[i][0] == pubkey) {
            e.eventData.newLikes.add(pubkey);
            hasReacted = true;
            break;
          }
        }
      }
    }

    bool childMatches = false;
    for( int i = 0; i < children.length; i++ ) {
      if( children[i].hasUserPostAndLike(pubkey)) {
        childMatches = true;
      }
    }
    if( e.eventData.pubkey == pubkey) {
      e.eventData.isNotification = true;
      return true;
    }
    if( hasReacted || childMatches) {
      return true;
    }
    return false;
  } 

  // returns true if the given words exists in it or its children
  bool hasWords(String word) {
    //if(gDebug > 0) print("In tree selector hasWords: this id = ${e.eventData.id} word = $word");
    if( e.eventData.content.length > 1000) {
      return false;
    }
    bool childMatches = false;
    for( int i = 0; i < children.length; i++ ) {
      // ignore too large comments
      if( children[i].e.eventData.content.length > 1000) {
        continue;
      }

      if( children[i].hasWords(word)) {
        childMatches = true;
      }
    }

    if( e.eventData.content.toLowerCase().contains(word)) {
      e.eventData.isNotification = true;
      return true;
    }
    if( childMatches) {
      return true;
    }
    return false;
  } 

  // returns true if the event or any of its children were made from the given client, and they are marked for notification
  bool fromClientSelector(String clientName) {
    //if(gDebug > 0) print("In tree selector hasWords: this id = ${e.eventData.id} word = $word");

    bool byClient = false;
    List<List<String>> tags = e.eventData.tags;
    for( int i = 0; i < tags.length; i++) {
      if( tags[i].length < 2) {
        continue;
      }
      if( tags[i][0] == "client" && tags[i][1].contains(clientName)) {
        e.eventData.isNotification = true;
        byClient = true;
        break;
      }
    }

    bool childMatch = false;
    for( int i = 0; i < children.length; i++ ) {
      if( children[i].fromClientSelector(clientName)) {
        childMatch = true;
      }
    }
    if( byClient || childMatch) {
      //print("SOME matched $clientName ");
      return true;
    }
    //print("none matched $clientName ");

    return false;
  } 

  Event? getContactEvent(String pkey) {
      // get the latest kind 3 event for the user, which lists his 'follows' list
      int latestContactsTime = 0;
      String latestContactEvent = "";

      allChildEventsMap.forEach((key, value) {
        if( value.e.eventData.pubkey == pkey && value.e.eventData.kind == 3 && latestContactsTime < value.e.eventData.createdAt) {
          latestContactEvent = value.e.eventData.id;
          latestContactsTime = value.e.eventData.createdAt;
        }
      });

      // if contact list was found, get user's feed, and keep the contact list for later use 
      if (latestContactEvent != "") {
        if( gDebug > 0) {
          print("latest contact event : $latestContactEvent with total contacts = ${allChildEventsMap[latestContactEvent]?.e.eventData.contactList.length}");
          print(allChildEventsMap[latestContactEvent]?.e.originalJson);
        }
        return allChildEventsMap[latestContactEvent]?.e;
      }

      return null;
  }

  // TODO inefficient; fix
  List<String> getFollowers(String pubkey) {
    if( gDebug > 0) print("Finding followrs for $pubkey");
    List<String> followers = [];

    Set<String> usersWithContactList = {};
    allChildEventsMap.forEach((key, value) {
      if( value.e.eventData.kind == 3) {
        usersWithContactList.add(value.e.eventData.pubkey);
      }
    });

    usersWithContactList.forEach((x) { 
      Event? contactEvent = getContactEvent(x);

      if( contactEvent != null) {
        List<Contact> contacts = contactEvent.eventData.contactList;
        for(int i = 0; i < contacts.length; i ++) {
          if( contacts[i].id == pubkey) {
            followers.add(x);
            return;
          }
        }
      }
    });

    return followers;
  }

  void printSocialDistance(String otherPubkey, String otherName) {
    String otherName = getAuthorName(otherPubkey);

    List<String> contactList = [];
    Event? contactEvent = this.getContactEvent(userPublicKey);
    bool isFollow = false;
    int  numSecond = 0; // number of your follows who follow the other

    int numContacts =  0;
    if( contactEvent != null) {
      List<Contact> contacts = contactEvent.eventData.contactList;
      numContacts = contacts.length;
      for(int i = 0; i < contacts.length; i ++) {
        // check if you follow the other account
        if( contacts[i].id == otherPubkey) {
          isFollow = true;
        }
        // count the number of your contacts who know or follow the other account
        List<Contact> followContactList = [];
        Event? followContactEvent = this.getContactEvent(contacts[i].id);
        if( followContactEvent != null) {
          followContactList = followContactEvent.eventData.contactList;
          for(int j = 0; j < followContactList.length; j++) {
            if( followContactList[j].id == otherPubkey) {
              numSecond++;
              break;
            }
          }
        }
      }// end for loop through users contacts
      print("\n\n");
      if( isFollow) {
        print("* You follow $otherName ");
      }
      print("* Of the $numContacts people you follow, $numSecond follow $otherName");

    } // end if contact event was found
  }
} // end Tree

void addMessageToChannel(String channelId, String messageId, var tempChildEventsMap, var chatRooms) {
  //chatRooms[channelId]?.messageIds.add(newTree.e.eventData.id);
  int newEventTime = (tempChildEventsMap[messageId]?.e.eventData.createdAt??0);

  if( chatRooms.containsKey(channelId)) {
    ChatRoom? room = chatRooms[channelId];
    if( room != null ) {
      if( room.messageIds.isEmpty) {
        if(gDebug> 0) print("room is empty. adding new message and returning. ");
        room.messageIds.add(messageId);
        return;
      }
      if(gDebug> 0) print("room has ${room.messageIds.length} messages already. adding new one to it. ");

      for(int i = 0; i < room.messageIds.length; i++) {
        int eventTime = (tempChildEventsMap[room.messageIds[i]]?.e.eventData.createdAt??0);
        if( newEventTime < eventTime) {
          // shift current i and rest one to the right, and put event Time here
          room.messageIds.insert(i, messageId);
          return;
        }
      }
      // insert at end
      room.messageIds.add(messageId);
      return;
    } else {
      print("In addMessageToChannel: could not find room");
    }
  } else {
    print("In addMessageToChannel: could not find channel id");
  }
  print("In addMessageToChannel: returning without inserting message");
}

int ascendingTimeTree(Tree a, Tree b) {
  if(a.e.eventData.createdAt < b.e.eventData.createdAt) {
    return -1;
  } else {
    if( a.e.eventData.createdAt == b.e.eventData.createdAt) {
      return 0;
    }
  }
  return 1;
}

// sorter function that looks at the latest event in the whole tree including the/its children
int sortTreeNewestReply(Tree a, Tree b) {
  int aMostRecent = a.getMostRecentTime(0);
  int bMostRecent = b.getMostRecentTime(0);

  if(aMostRecent < bMostRecent) {
    return -1;
  } else {
    if( aMostRecent == bMostRecent) {
      return 0;
    } else {
        return 1;
    }
  }
}

// for the given reaction event of kind 7, will update the global gReactions appropriately, returns 
// the reactedTo event's id, blank if invalid reaction etc
String processReaction(Event event) {
  if( event.eventData.kind == 7 && event.eventData.eTagsRest.isNotEmpty) {
    if(gDebug > 1) ("Got event of type 7");
    String reactorId  = event.eventData.pubkey;
    String comment    = event.eventData.content;
    int    lastEIndex = event.eventData.eTagsRest.length - 1;
    String reactedTo  = event.eventData.eTagsRest[lastEIndex];
    if( gReactions.containsKey(reactedTo)) {
      // check if the reaction already exists by this user
      for( int i = 0; i < ((gReactions[reactedTo]?.length)??0); i++) {
        List<String> oldReaction = (gReactions[reactedTo]?[i])??[];
        if( oldReaction.length == 2) {
          //valid reaction
          if(oldReaction[0] == reactorId) {
            return ""; // reaction by this user already exists so return
          }
        }
      }

      List<String> temp = [reactorId, comment];
      gReactions[reactedTo]?.add(temp);
    } else {
      List<List<String>> newReactorList = [];
      List<String> temp = [reactorId, comment];
      newReactorList.add(temp);
      gReactions[reactedTo] = newReactorList;
    }
    return reactedTo;
  }
  return "";
}

// will go over the list of events, and update the global gReactions appropriately
void processReactions(List<Event> events) {
  for (Event event in events) {
    processReaction(event);
  }
  return;
}

/*
 * @function getTree Creates a Tree out of these received List of events. 
 */
Future<Tree> getTree(List<Event> events) async {
    if( events.isEmpty) {
      print("Warning: In printEventsAsTree: events length = 0");
      return Tree(Event("","",EventData("non","", 0, 0, "", [], [], [], [[]], {}), [""], "[json]"), [], {}, [], true, {});
    }

    // populate the global with display names which can be later used by Event print
    events.forEach( (x) => processKind0Event(x));

    // process NIP 25, or event reactions by adding them to a global map
    processReactions(events);

    // remove all events other than kind 0, 1, 3, 7  and 40 (chat rooms)
    events.removeWhere( (item) => !Tree.typesInEventMap.contains(item.eventData.kind));  

    // remove bot events
    events.removeWhere( (item) => gBots.contains(item.eventData.pubkey));

    // remove duplicate events
    Set ids = {};
    events.retainWhere((x) => ids.add(x.eventData.id));

    // translate and expand mentions for all
    events.forEach( (e) => e.eventData.translateAndExpandMentions());

    // create tree from events
    Tree node = Tree.fromEvents(events);

    if(gDebug != 0) print("total number of events in main tree = ${node.count()}");
    return node;
}
