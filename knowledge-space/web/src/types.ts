export type Entity = {id:string;stable_key:string;kind:string;label:string;definition:string;domain_weights:Record<string,number>;granularity:number;source_uri?:string;status:string};
export type Relation = {id:string;source_id:string;target_id:string;relation_type:string;evidence:string;status:string};
