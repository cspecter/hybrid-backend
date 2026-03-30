// Sync Edge Function - Processes changes from OLD DB and applies to NEW DB
// Deploy to OLD Supabase project
//
// NEW SCHEMA CHANGES:
// - New database uses INTEGER primary keys (auto-incrementing)
// - OLD UUID IDs are stored as public_id in new schema
// - This function handles UUID -> INT mapping

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// Configuration
const NEW_DB_URL = Deno.env.get("NEW_SUPABASE_URL")!;
const NEW_DB_SERVICE_KEY = Deno.env.get("NEW_SUPABASE_SERVICE_ROLE_KEY")!;
const OLD_DB_URL = Deno.env.get("SUPABASE_URL")!;
const OLD_DB_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Table mapping: old table name -> new table name
const TABLE_MAP: Record<string, string> = {
  users: "profiles",
  dispensary_locations: "locations",
  dispensary_employees: "location_employees",
  products_brands: "product_brands",
  products_products: "related_products",
  deals_dispensary_locations: "deals_locations",
  user_blocks: "profile_blocks",
  user_brand_admins: "profile_admins",
  posts_users: "posts_profiles",
  auth_users: "auth.users",
};

// Column mapping: old column name -> new column name
const COLUMN_MAP: Record<string, Record<string, string>> = {
  users: {
    name: "display_name",
    description: "bio",
    profile_picture_id: "avatar_url",
    banner_id: "banner_url",
    home_location: "home_location_id",
    verified: "is_verified",
    date_created: "created_at",
    date_updated: "updated_at",
    fts_vector: "fts",
  },
  dispensary_locations: {
    address1: "address_line1",
    address2: "address_line2",
    brand_id: "brand_id", // Will need UUID resolution
    date_created: "created_at",
    date_updated: "updated_at",
    fts_vector: "fts",
  },
  dispensary_employees: {
    dispensary_id: "location_id",
    user_id: "profile_id",
    date_created: "created_at",
    date_modified: "updated_at",
  },
  products: {
    date_created: "created_at",
    date_updated: "updated_at",
    fts_vector: "fts",
  },
  products_brands: {
    products_id: "product_id",
    users_id: "brand_id",
  },
  products_products: {
    products_id: "product_id",
    products_related_id: "related_product_id",
    date_created: "created_at",
  },
  deals_dispensary_locations: {
    deals_id: "deal_id",
    dispensary_locations_id: "location_id",
  },
  user_blocks: {
    user_id: "blocker_id",
    block_id: "blocked_id",
    date_created: "created_at",
  },
  user_brand_admins: {
    user_id: "admin_profile_id",
    brand_id: "managed_profile_id",
  },
  posts_users: {
    user_id: "profile_id",
    date_created: "created_at",
  },
  posts: {
    user_id: "profile_id",
    date_created: "created_at",
    date_updated: "updated_at",
    fts_vector: "fts",
  },
  notifications: {
    user_id: "profile_id",
    read: "is_read",
    date_created: "created_at",
  },
  relationships: {
    date_created: "created_at",
    date_updated: "updated_at",
  },
  likes: {
    user_id: "profile_id",
    date_created: "created_at",
  },
  stash: {
    user_id: "profile_id",
    date_created: "created_at",
  },
  deals: {
    user_id: "profile_id",
    date_created: "created_at",
    date_updated: "updated_at",
  },
  lists: {
    user_id: "profile_id",
    date_created: "created_at",
    date_updated: "updated_at",
  },
  giveaways: {
    user_id: "profile_id",
    date_created: "created_at",
    date_updated: "updated_at",
    fts_vector: "fts",
  },
  giveaway_entries: {
    user_id: "profile_id",
    date_created: "created_at",
  },
};

// FK columns that need UUID -> INT resolution
// Maps column name to the table name for resolution
const FK_COLUMNS: Record<string, Record<string, string>> = {
  users: {
    home_location: "locations",
  },
  dispensary_locations: {
    brand_id: "profiles",
  },
  dispensary_employees: {
    dispensary_id: "locations",
    user_id: "profiles",
  },
  products_brands: {
    products_id: "products",
    users_id: "profiles",
  },
  products_products: {
    products_id: "products",
    products_related_id: "products",
  },
  deals_dispensary_locations: {
    deals_id: "deals",
    dispensary_locations_id: "locations",
  },
  user_blocks: {
    user_id: "profiles",
    block_id: "profiles",
  },
  user_brand_admins: {
    user_id: "profiles",
    brand_id: "profiles",
  },
  posts_users: {
    post_id: "posts",
    user_id: "profiles",
  },
  posts: {
    user_id: "profiles",
    location_id: "locations",
  },
  notifications: {
    user_id: "profiles",
    actor_id: "profiles",
    post_id: "posts",
    product_id: "products",
    giveaway_id: "giveaways",
    list_id: "lists",
  },
  relationships: {
    follower_id: "profiles",
    followee_id: "profiles",
  },
  likes: {
    user_id: "profiles",
    post_id: "posts",
  },
  stash: {
    user_id: "profiles",
    product_id: "products",
    source_id: "profiles", // Could be list, post, or profile - handled specially
  },
  posts_products: {
    post_id: "posts",
    product_id: "products",
  },
  posts_hashtags: {
    post_id: "posts",
  },
  lists: {
    user_id: "profiles",
  },
  lists_products: {
    list_id: "lists",
    product_id: "products",
  },
  deals: {
    user_id: "profiles",
  },
  giveaways: {
    user_id: "profiles",
  },
  giveaway_entries: {
    giveaway_id: "giveaways",
    user_id: "profiles",
  },
};

// Cache for UUID -> INT mappings
const uuidToIntCache = new Map<string, number>();

// Get INT ID from UUID using new DB lookup (with caching)
async function resolveUuidToInt(
  newDb: SupabaseClient,
  tableName: string,
  uuid: string | null
): Promise<number | null> {
  if (!uuid) return null;
  
  const cacheKey = `${tableName}:${uuid}`;
  
  // Check cache first
  if (uuidToIntCache.has(cacheKey)) {
    return uuidToIntCache.get(cacheKey)!;
  }
  
  // Query new DB for the INT id based on public_id (which stores the old UUID)
  const { data, error } = await newDb
    .from(tableName)
    .select("id")
    .eq("public_id", uuid)
    .single();
  
  if (error || !data) {
    console.warn(`Could not resolve UUID ${uuid} for table ${tableName}`);
    return null;
  }
  
  // Cache the result
  uuidToIntCache.set(cacheKey, data.id);
  return data.id;
}

// Transform old data to new schema
async function transformData(
  newDb: SupabaseClient,
  tableName: string,
  data: Record<string, unknown>
): Promise<Record<string, unknown>> {
  const columnMap = COLUMN_MAP[tableName] || {};
  const fkColumns = FK_COLUMNS[tableName] || {};
  const result: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(data)) {
    // Skip the old 'id' column - will be auto-generated
    if (key === "id") {
      // Store old UUID as public_id
      result.public_id = value;
      continue;
    }
    
    // Check if this is a FK column that needs UUID resolution
    if (fkColumns[key] && value) {
      const targetTable = fkColumns[key];
      const intId = await resolveUuidToInt(newDb, targetTable, value as string);
      
      // Use the mapped column name
      const newKey = columnMap[key] || key;
      result[newKey] = intId;
      continue;
    }
    
    // Regular column rename
    const newKey = columnMap[key] || key;
    result[newKey] = value;
  }

  // Special transformations
  if (tableName === "users") {
    // Add auth_id (same as original UUID id)
    result.auth_id = result.public_id;
    
    // Determine profile_type based on role_id
    const roleId = data.role_id as number;
    const brandRoleIds = [1, 2, 3, 4, 5];
    result.profile_type = brandRoleIds.includes(roleId) ? "brand" : "individual";
    
    // Build business_info for brand profiles
    if (brandRoleIds.includes(roleId)) {
      result.business_info = {
        migrated_from_old_db: true,
        original_role_id: roleId,
        synced_at: new Date().toISOString(),
      };
    } else {
      result.business_info = null;
    }
  }

  if (tableName === "dispensary_employees") {
    // Convert is_admin boolean to role enum
    result.role = data.is_admin ? "manager" : "employee";
    delete result.is_admin;
    delete result.has_been_reviewed;
  }

  // Remove columns that don't exist in new schema
  const removedColumns: Record<string, string[]> = {
    users: ["password", "salt", "token", "provider", "fts_vector"],
    posts: ["file_id"],
    dispensary_employees: ["is_admin", "has_been_reviewed"],
  };

  for (const col of removedColumns[tableName] || []) {
    delete result[col];
  }

  return result;
}

// Insert or update in new DB using public_id for lookup
async function upsertToNewDb(
  newDb: SupabaseClient,
  tableName: string,
  data: Record<string, unknown>,
  publicId: string
): Promise<{ id: number | null; error: Error | null }> {
  const newTableName = TABLE_MAP[tableName] || tableName;
  
  // First, check if record exists by public_id
  const { data: existing } = await newDb
    .from(newTableName)
    .select("id")
    .eq("public_id", publicId)
    .single();
  
  if (existing) {
    // Update existing record
    const { error } = await newDb
      .from(newTableName)
      .update(data)
      .eq("id", existing.id);
    
    return { id: existing.id, error };
  } else {
    // Insert new record (id will be auto-generated)
    const { data: inserted, error } = await newDb
      .from(newTableName)
      .insert(data)
      .select("id")
      .single();
    
    return { id: inserted?.id || null, error };
  }
}

Deno.serve(async (req) => {
  try {
    // Create clients
    const oldDb = createClient(OLD_DB_URL, OLD_DB_SERVICE_KEY);
    const newDb = createClient(NEW_DB_URL, NEW_DB_SERVICE_KEY, {
      db: { schema: "public" },
    });

    // Fetch unsynced items from queue using the helper function
    const { data: queueItems, error: fetchError } = await oldDb.rpc(
      "get_pending_syncs",
      { p_limit: 100 }
    );

    if (fetchError) {
      // Fallback to direct query if function doesn't exist
      const { data: fallbackItems, error: fallbackError } = await oldDb
        .from("sync_queue")
        .select("*")
        .eq("synced", false)
        .lt("sync_attempts", 5)
        .order("created_at", { ascending: true })
        .limit(100);

      if (fallbackError) throw fallbackError;
      
      // Process with fallback format
      return await processItems(oldDb, newDb, fallbackItems || [], false);
    }

    return await processItems(oldDb, newDb, queueItems || [], true);
  } catch (error) {
    console.error("Sync function error:", error);
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

async function processItems(
  oldDb: SupabaseClient,
  newDb: SupabaseClient,
  queueItems: unknown[],
  hasResolvedFks: boolean
): Promise<Response> {
  if (!queueItems || queueItems.length === 0) {
    return new Response(JSON.stringify({ message: "No items to sync" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  console.log(`Processing ${queueItems.length} sync items`);

  const results = {
    success: 0,
    failed: 0,
    errors: [] as string[],
  };

  for (const item of queueItems as Record<string, unknown>[]) {
    try {
      const queueId = hasResolvedFks ? item.queue_id : item.id;
      const tableName = item.table_name as string;
      const operation = item.operation as string;
      const oldData = item.old_data as Record<string, unknown> | null;
      const newData = item.new_data as Record<string, unknown> | null;
      const entityUuid = (item.entity_uuid || oldData?.id || newData?.id) as string;
      
      const newTableName = TABLE_MAP[tableName] || tableName;
      const isAuthTable = tableName === "auth_users";

      if (operation === "INSERT" || operation === "UPDATE") {
        if (!newData) {
          throw new Error("No new_data for INSERT/UPDATE operation");
        }
        
        const transformedData = await transformData(newDb, tableName, newData);

        if (isAuthTable) {
          // Handle auth.users separately using admin API
          const { error } = await newDb.auth.admin.updateUserById(
            entityUuid,
            {
              email: transformedData.email as string,
              phone: transformedData.phone as string | undefined,
              email_confirm: !!transformedData.email_confirmed_at,
              user_metadata: transformedData.raw_user_meta_data as Record<
                string,
                unknown
              >,
              app_metadata: transformedData.raw_app_meta_data as Record<
                string,
                unknown
              >,
            }
          );

          if (error) {
            console.log(
              `Auth user sync note: ${error.message} for ${entityUuid}`
            );
          }
        } else {
          // Upsert to new table using public_id
          const { id: newIntId, error } = await upsertToNewDb(
            newDb,
            tableName,
            transformedData,
            entityUuid
          );

          if (error) {
            throw error;
          }

          // Mark as synced and store the mapping
          await oldDb.rpc("mark_synced", {
            p_queue_id: queueId,
            p_table_name: newTableName,
            p_old_uuid: entityUuid,
            p_new_int_id: newIntId,
          });
          
          results.success++;
          continue; // Skip the generic mark as synced below
        }
      } else if (operation === "DELETE") {
        if (!oldData?.id) {
          throw new Error("No id in old_data for DELETE operation");
        }

        if (isAuthTable) {
          // Don't auto-delete auth users - too dangerous
          console.log(`Auth user delete skipped (manual review): ${entityUuid}`);
        } else {
          // Delete by public_id in new DB
          const { error } = await newDb
            .from(newTableName)
            .delete()
            .eq("public_id", entityUuid);

          if (error) {
            throw error;
          }
        }
      }

      // Mark as synced (fallback for when mark_synced RPC isn't available)
      await oldDb
        .from("sync_queue")
        .update({ synced: true })
        .eq("id", queueId);

      results.success++;
    } catch (error) {
      const queueId = hasResolvedFks
        ? (item as Record<string, unknown>).queue_id
        : (item as Record<string, unknown>).id;
      const tableName = (item as Record<string, unknown>).table_name;
      
      console.error(`Error syncing item ${queueId}:`, error);

      // Update sync attempt count
      await oldDb
        .from("sync_queue")
        .update({
          sync_attempts:
            ((item as Record<string, unknown>).sync_attempts as number || 0) + 1,
          last_sync_attempt: new Date().toISOString(),
          error_message: String(error),
        })
        .eq("id", queueId);

      results.failed++;
      results.errors.push(`${tableName}:${queueId} - ${error}`);
    }
  }

  return new Response(JSON.stringify(results), {
    headers: { "Content-Type": "application/json" },
  });
}
