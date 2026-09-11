/* Club IMPORTB2B V3 - módulo multi-club para integrar en admin.
   Requiere window.clubSupabase y la migración V3. */
window.ClubMulti = {
  labels:{vapers:"Club Vapers",jerseys:"Club Jerseys",perfumes:"Club Perfumes",importb2b:"Club IMPORTB2B"},
  async getClubs(clientId){
    const {data,error}=await window.clubSupabase.rpc("admin_get_client_clubs",{p_client_id:clientId});
    if(error) throw error; return data||[];
  },
  async addClub(clientId,clubType){
    const {data,error}=await window.clubSupabase.rpc("admin_add_client_to_club",{p_client_id:clientId,p_club_type:clubType});
    if(error) throw error; return data;
  },
  async registerPurchase(clientId,clubType,amount=null,observation=null){
    const {data,error}=await window.clubSupabase.rpc("admin_register_verified_purchase_v3",{
      p_client_id:clientId,p_club_type:clubType,p_purchase_amount:amount,p_observation:observation
    });
    if(error) throw error; return data;
  }
};
